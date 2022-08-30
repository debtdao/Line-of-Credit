import ERC20 from vyper.interfaces

interface ERC2612:
  def permit(owner: address, spender: address, value: uint256, deadline: uint256, v: uint8, r: bytes32, s: bytes32) external
  def nonces(address owner) external view returns (uint)
  def DOMAIN_SEPARATOR() external view returns (bytes32)

implements: ERC20, ERC2612

contract LineOfCredit:
    def status() -> uint256: constant
    def credits(id: bytes32) constant

    def addCredit(
      drate: uint128,
      frate: uint128,
      amount: uint256,
      token: address,
      lender: address
    ): modifying
    def setRates(id: bytes32 , drate: uint128, frate: uint128) modifying
    def increaseCredit(id: bytes32,  amount: uint25) modifying
    

# Pool vars

# asset manager who directs funds into investment strategies
delegate: public(address)
# minimum amount of assets that can be deposited at once. whales only, fuck plebs.
minDeposit: public(uint256)
# amount of asset held externally in lines or vaults
totalDeployed: public(uint256)
# amount of assets written down after line defaulted.
# only stores initial deposit remaining. doesnt track total owed w/ interest
impaired: public(HashMap[address, uint256])
# LineLib.STATUS.INSOLVENT
INSOLVENT_STATUS: constant(4)


#ERC20 vars
totalSupply: public(uint256)
name: string[50]
symbol: string[10]

balances: HashMap[address, uint256]
# owner -> spender -> amount approved
allowances: HashMap[address, HashMap[address, uint256]]

# ERC20 Events

# ERC4626 vars
asset: immutable(address)
totalAssets: public(uint256)

# ERC4626 Events

# TODO add permit

@external
def __init__
  delegate_: address,
  asset_: address,
  name_: string[50],
  symbol_: string[10]
):
  """
  @dev configure data for contract owners and initial revenue contracts.
       Owner/operator/treasury can all be the same address
  @param

  """
  # ERC20 vars
  self.name = name_
  self.symbol = symbol_
  #ERC4626
  self.asset = asset_
  # DelegatePool
  self.delegate = delegate_


# Delegate functions

@external
def impair(line: address, id: bytes32):
  assert LineOfCredit(line).status() == INSOLVENT_STATUS

  (uint256 principal, uint256 deposit,, uint256 interestPaid,,,) = LineOfCredit(line).credits(id)

  claimable: uint256 = interestPaid + (deposit - principal)
  impaired[line] += principal  # write down lost principal
  
  if claimable > 0:
    LineOfCredit(line).withdraw(claimable)
    diff = principal - interestPaid  # reduce diff by recovered funds

  self._updateShares(diff, True)

@external
def addCredit(
  line: address,
  drate: uint128,
  frate: uint128,
  amount: uint256
):
  assert msg.sender is delegate
  self.deployed += amount
  LineOfCredit(line).addCredit(drate, frate, amount, token, self.address)

@external
def increastCredit(
  line: address,
  id: bytes32,
  amount: uint256
):
  assert msg.sender is delegate
  self.deployed += amount
  LineOfCredit(line).increaseCredit(id, amount)

@external
def reduceCredit(
  line: address,
  id: bytes32,
  amount: uint256
):
  assert msg.sender is delegate

  # store how much interest is currently claimable
  (,interest: uint256) = LineOfCredit(line).available(id)
  LineOfCredit(line).withdraw(id, amount)

  # LoC always sends profits before principal so will always have a value
  collected = amount if amount < interest else interest 
  # update share price with new profits
  self._updateShares(collected, false)

  # assume principal was also drawn otherwise they would call collect()
  self.deployed -= amount - collected


@external
def setRates(
  line: address,
  id: bytes32,
  drate: uint128,
  frate: uint128,
):
  assert msg.sender is delegate
  LineOfCredit(line).setRates(id, drate, frate)


@external
def collect(
  line: address,
  id: bytes32
):
  (,amount: uint256) = LineOfCredit(line).available(id)
  LineOfCredit(line).withdraw(id, amount)
  # TODO add compounder fee
  self._updateShares(amount, false)
  # emit deposit


@external
def deposit(assets: uint256, to: address):
  """
    adds assets
  """
  # TODO convert assets
  self._deposit(amount / self._getSharePrice(), amount, to)
  # emit deposit

@external
def mint(shares: uint256, to: address):
  """
    adds shares
  """
  self._deposit(shares, amount * self._getSharePrice(), to)
  # emit deposit

@external
def withdraw(
  amount: uint256,
  receiver: address,
  owner: address
):
  assert reciever == owner or allowances[owner][msg.sender] >= amount
  allowances[owner][msg.sender] -= amount
  self._withdraw(amount / self._getSharePrice(), amount, to)


@external
def redeem(shares: uint256, to: address, owner: address):
  """
    adds shares
  """
  assert msg.sender == owner or allowances[owner][msg.sender] >= amount
  allowances[owner][msg.sender] -= amount
  self._withdraw(shares, amount * self._getSharePrice(), to)
  # emit deposit


# pool interals

@internal
def _deposit(
  shares: uint256,
  assets: uint256,
  to: address
):
  totalAssets += amount
  balances[to] += shares
  assert ERC20(asset).transferFrom(msg.sender, self.address, amount)     

@internal
def _withdraw(
  shares: uint256,
  assets: uint256,
  to: address
):
  assert assets <= totalAssets - totalDeployed

  totalAssets -= amount
  balances[to] -= shares
  assert ERC20(asset).transfer(to, amount)     


# ERC20 view functions

@external
@view
def balanceOf(account: address):
  return self.balances[account]

@external
@view
def decimals():
  return 18

@external
@view
def totalSupply():
  return self.totalSupply

@external
@view
def name():
  return self.name

@external
@view
def symbol():
  return self.symbol

@external
@view
def allowance(owner: address, spender: address):
  return self.allowances[owner][spender]

# ERC4626 view functions

@external
@view
def asset():
  return self.asset

@external
@view
def totalAssets():
  return self.totalAssets


@external
@view
def assetsToShares(amount: uint256):
  return amount * (self.totalAssets / self.totalSupply)


@external
@view
def sharesToAssets(amount: uint256):
  return amount * (self.totalSupply / self.totalAssets)


@external
@view
def maxDeposit():
  """
    add assets
  """
  return MAX_UINT256 - totalAssets

@external
@view
def maxMint():
  return MAX_UINT256 - totalAssets

@external
@view
def maxWithdraw(owner: address):
  """
    remove shares
  """
  return self._getMaxLiquidAssets()

@external
@view
def maxRedeem(owner: address):
  """
    remove assets
  """
  return self._getMaxLiquidAssets() / self._getSharePrice()

@external
@view
def previewMint():
  # MUST be inclusive of deposit fees
  return MAX_UINT256 - totalAssets


@external
@view
def previewWithdraw():
  # MUST be inclusive of withdraw fees
  return MAX_UINT256 - totalAssets

@external
@view
def previewRedeem():
  # MUST be inclusive of withdraw fees
  return MAX_UINT256 - totalAssets


# ERC20 action functions

@external
def transfer(to: address, amount: uint256):
  self.balance[msg.sender] -= amount
  self.balance[to] -= amount
  # log
  return True


@external
def transferFrom(from: address, to: address, amount: uint256):
  assert self.allowances[from][msg.sender] >= amount
  self.allowances[from][msg.sender] -= amount
  self.balance[from] -= amount
  self.balance[to] -= amount
  # log
  return True

@external
def approve(spender: address, amount: uint256):
  self.allowances[msg.sender][spender] = amount
  # log
  return True

@external
def increaseAllowance(spender: address, amount: uint256):
  self.allowances[msg.sender][spender] += amount
  # log
  return True


# ERC4626 internal functions
@internal
def _updateShares(amount: uint256, impair: bool):
  if impair:
    totalAssets -= amount
    # TODO RDT logic
  else:
    totalAssets += amount
    # TODO RDT logic

@internal
def _getSharePrice():
  # TODO RDT logic
  return totalAssets / totalSupply

@internal
def _getMaxLiquidAssets():
  available = totalAssets - totalDeployed
  total = balances[owner] * self._getSharePrice() 
  return total if available > total else available


  
# TODO ERC2612 permit, nonce, DOMAIN _SEPERATOR
