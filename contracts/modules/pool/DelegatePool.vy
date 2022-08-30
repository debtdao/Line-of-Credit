import ERC20 from vyper.interfaces

implements: ERC20

contract LineOfCredit:
    def status() -> uint256: constant
    def addCredit(
      drate: uint128,
      frate: uint128,
      amount: uint256,
      token: address,
      lender: address
    ): modifying


# Pool vars
delegate: public(address)
min_deposit: public(uint256)
totalDeployed: public(uint256) # amount of asset held in lines

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


@external
def __init__
  delegate_: address,
  asset_: address,
  name: string[50],
  symbol: string[10]
):
  """
  @dev configure data for contract owners and initial revenue contracts.
       Owner/operator/treasury can all be the same address
  @param

  """
  self.asset = asset_
  self.delegate = delegate_


# Delegate functions

@external
def impair(line: address):

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
  # store how much interest is claimable
  # LoC always sends profits before principal so will always have a value
  (,available: uint256) = LineOfCredit(line).available(id)
  LineOfCredit(line).withdraw(id, amount)
  collected = amount if amount < available else available 
  self._updateShares(collected, false)

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
  assert msg.sender is delegate
  (,amount: uint256) = LineOfCredit(line).available(id)
  LineOfCredit(line).withdraw(id, amount)
  self._updateShares(amount, false)
  # emit deposit


@external
def deposit(amount: uint256, to: address):
  self._deposit(amount, to)
  # emit deposit

@external
def mint(amount: uint256, to: address):
  self._deposit(amount, to)
  # emit deposit

@external
def withdraw(
  amount: uint256,
  receiver: address,
  owner: address
):
  assert allowances[owner][msg.sender] >= amount
  allowances[owner][msg.sender] -= amount
  self._withdraw(receiver, amount)


# pool interals


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
  return MAX_UINT256 - totalAssets

@external
@view
def maxMint():
  return MAX_UINT256 - totalAssets

@external
@view
def maxWithdraw(owner: address):
  available = totalAssets - totalDeployed
  total = balances[owner] * self._getSharePrice() 
  return total if available > total else available

@external
@view
def previewMint():
  # MUST be inclusive of deposit fees
  return MAX_UINT256 - totalAssets

@external
@view
def previewWithdraw():
  # MUST be inclusive of deposit fees
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
      # TODO
    else:
      totalAssets += amount
      # TODO

@internal
def _getSharePrice():
    return totalAssets / totalSupply
      
@internal
def _deposit(amount: uint256, to: address):
  shares: uint256 =  amount / self._getSharePrice()
  totalAssets += amount
  balances[to] += shares
  assert ERC20(asset).transferFrom(msg.sender, self.address, amount)     

@internal
def _withdraw(amount: uint256, to: address):
  shares: uint256 =  amount / self._getSharePrice()
  totalAssets -= amount
  balances[to] -= shares
  assert ERC20(asset).transfer(to, amount)     
