from vyper.interfaces import ERC20 

interface ERC2612:
  def permit(owner: address, spender: address, value: uint256, deadline: uint256, v: uint8, r: bytes32, s: bytes32): view
  def nonces(owner: address ) -> uint256: view
  def DOMAIN_SEPARATOR() -> bytes32: view

interface ERC4626:
  def deposit(assets: uint256, to: address)  -> bool: payable
  def withdraw(assets: uint256, to: address) -> bool: payable


interface LineOfCredit:
    def status() -> uint256: constant
    def credits(id: bytes32): constant

    def addCredit(
      drate: uint128,
      frate: uint128,
      amount: uint256,
      token: address,
      lender: address
    ): modifying
    def setRates(id: bytes32 , drate: uint128, frate: uint128): modifying
    def increaseCredit(id: bytes32,  amount: uint25): modifying
    
implements: [ERC20, ERC2612, ERC4626]

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
# shares earned by Delegate for managing pool
delegateFees: uint256
# % of profit that delegate keeps as incentives
performanceFeeNumerator: uint8
# % of performance fee to give to caller for automated collections
collectorFeeNumerator: uint8

#ERC20 vars
name: string[50]
symbol: string[10]
# total amount of shares in pool
totalSupply: public(uint256)
# balance of pool vault shares
balances: HashMap[address, uint256]
# owner -> spender -> amount approved
allowances: HashMap[address, HashMap[address, uint256]]

# ERC20 Events

# ERC4626 vars
# underlying token for pool/vault
asset: immutable(address)
# total notional amount of underlying token held in pool
totalAssets: public(uint256)

# ERC4626 Events

# TODO add permit

@external
def __init__(
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
  """
    @notice     - allows Delegate to markdown the value of a defaulted loan reducing vault share price.
    @param line - line of credit contract to call
    @param id   - credit position on line controlled by this pool 
  """
  assert LineOfCredit(line).status() == INSOLVENT_STATUS

  (uint256 principal, uint256 deposit,, uint256 interestPaid,,,) = LineOfCredit(line).credits(id)

  claimable: uint256 = interestPaid + (deposit - principal) # all funds let in line
  impaired[line] += principal  # write down lost principal
  
  if claimable > 0:
    LineOfCredit(line).withdraw(claimable)
    diff = principal - interestPaid  # reduce diff by recovered funds

  # TODO take profermanceFee  from delegate to offset impairment and reduce diff
  # TODO currently callable by anyone. Should we give % of delegates fees to caller?
  self._updateShares(diff, True)

@external
def addCredit(
  line: address,
  drate: uint128,
  frate: uint128,
  amount: uint256
):
  assert msg.sender is delegate
  self.totalDeployed += amount
  LineOfCredit(line).addCredit(drate, frate, amount, token, self.address)

@external
def increaseCredit(
  line: address,
  id: bytes32,
  amount: uint256
):
  assert msg.sender is delegate
  self.totalDeployed += amount
  LineOfCredit(line).increaseCredit(id, amount)

@external
def invest4626(vault: address, amount: uint256):
  assert msg.sender is delegate
  self.totalDeployed += amount
  # TODO check previewDeposit expected vs deposit actual for slippage
  ERC4626(vault).deposit(amount, self.address)


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
  interestCollected = amount if amount < interest else interest 
  
  # update share price with new profits
  self._updateShares(interestCollected, False)

  # payout fees with new share price
  self._takeFees(interestCollected)

  # assume principal was also drawn otherwise they would call collect()
  self.totalDeployed -= amount - interestCollected


@external
def divest4626(vault: address, amount: uint256):
  assert msg.sender is delegate
  self.totalDeployed -= amount
  # TODO check previewWithdraw expected vs withdraw actual for slippage
  ERC4626(vault).withdraw(amount, self.address)
  # delegate doesnt earn fees on 4626 strategies to incentivize line investment


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
def collectInterest(
  line: address,
  id: bytes32
):
  (,interest: uint256) = LineOfCredit(line).available(id)
  LineOfCredit(line).withdraw(id, interest)
  # update share price with new profits
  self._updateShares(interest, False)
  # payout fees with new share price
  self._takeFees(interest)


# 4626 action functions

@external
def deposit(assets: uint256, to: address):
  """
    adds assets
  """
  self._deposit(amount / self._getSharePrice(), amount, to)

@external
def mint(shares: uint256, to: address):
  """
    adds shares
  """
  self._deposit(shares, amount * self._getSharePrice(), to)

@external
def withdraw(
  amount: uint256,
  receiver: address,
  owner: address
):
  assert msg.sender == owner or allowances[owner][msg.sender] >= amount
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
  # emit deposit

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
  # emit withdraw

@internal
def _takeFees(interestEarned: uint256):
  """
    @notice takes total profits earned and takes fees for delegate and compounder
    @dev fees are stored as shares but input/ouput assets
    @return total amount of assets taken as fees
  """
  if performanceFeeNumerator is 0:
    return 0

  totalFees: uint256 = interest * performanceFeeNumerator / 100
  collectorFee: uint256 = 0 if (
    collectorFeeNumerator is 0 or
    msg.sender is delegate
  ) else totalFees * collectorFeeNumerator / 100

  # caller gets collector fees in raw asset for easier mev
  ERC20(asset).transfer(msg.sender, collectorFee)
  totalAssets -= collectorFee

  # delegate gets performance fee.
  # Not stored in balance so we can differentiate fees earned vs their won deposits, letting us slash fees on impariment.
  # earn fees in shares, not raw asset, so profit is vested like other users
  sharePrice = self._getSharePrice()
  delegateFee: uint256 += (totalFees - collectorFee) / sharePrice
  self.delegateFees += delegateFee

  # inflate supply to reduce user share price
  self.totalSupply += delegateFee
  
  return totalFees

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
