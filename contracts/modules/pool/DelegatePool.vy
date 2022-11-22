# @version 0.2.16

from vyper.interfaces import ERC20

interface ERC2612:
  def permit(owner: address, spender: address, value: uint256, deadline: uint256, v: uint8, r: bytes32, s: bytes32): view
  def nonces(owner: address ) -> uint256: view
  def DOMAIN_SEPARATOR() -> bytes32: view

interface ERC4626:
  def deposit(assets: uint256, to: address)  -> uint256: payable
  def withdraw(assets: uint256, receiver: address, owner: address) -> uint256: payable
  def mint(shares: uint256, receiver: address) -> uint256: payable
  def redeem(shares: uint256, receiver: address, owner: address) -> uint256: payable
  # getters
  def asset() -> address: constant
  def totalAssets() -> address: view
  # @notice amount of shares that the Vault would exchange for the amount of assets provided
  def convertToShares(assets: uint256) -> uint256: view 
  # @notice amount of assets that the Vault would exchange for the amount of shares provided
  def convertToAssets(shares: uint256) -> uint256: view
  # @notice maximum amount of assets that can be deposited into vault for receiver
  def maxDeposit(receiver: address) -> uint256: view # @dev returns maxAssets
  # @notice simulate the effects of their deposit() at the current block, given current on-chain conditions.
  def previewDeposit(assets: uint256) -> uint256: view
  # @notice maximum amount of shares that can be deposited into vault for receiver
  def maxMint(receiver: address) -> uint256: view # @dev returns maxAssets
  # @notice simulate the effects of their mint() at the current block, given current on-chain conditions.
  def previewMint(shares: uint256) -> uint256: view
  # @notice maximum amount of assets that can be withdrawn into vault for receiver
  def maxWithdraw(receiver: address) -> uint256: view # @dev returns maxAssets
  # @notice simulate the effects of their withdraw() at the current block, given current on-chain conditions.
  def previewWithdraw(assets: uint256) -> uint256: view
  # @notice maximum amount of shares that can be withdrawn into vault for receiver
  def maxRedeem(receiver: address) -> uint256: view # @dev returns maxAssets
  # @notice simulate the effects of their redeem() at the current block, given current on-chain conditions.
  def previewRedeem(shares: uint256) -> uint256: view

interface ERC3156:
  # /**
  # * @dev The amount of currency available to be lent.
  # * @param token The loan currency.
  # * @return The amount of `token` that can be borrowed.
  # */
  def maxFlashLoan(token: address) -> uint256: view

  # /**
  # * @dev The fee to be charged for a given loan.
  # * @param token The loan currency.
  # * @param amount The amount of tokens lent.
  # * @return The amount of `token` to be charged for the loan, on top of the returned principal.
  # */
  def flashFee(token: address, amountL: uint256) -> uint256: view

  # /**
  # * @dev Initiate a flash loan.
  # * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
  # * @param token The loan currency.
  # * @param amount The amount of tokens lent.
  # * @param data Arbitrary data structure, intended to contain user-defined parameters.
  # */
  def flashLoan(
    receiver: IERC3156FlashBorrower,
    token: address,
    amount: uint256,
    data: DynArray[bytes, 25000]
  ) -> bool: modifying # should not be constant

# External Iinterfaces

interface IERC3156FlashBorrower:
  def onFlashLoan(
    initiator: address,
    token: address,
    amount: uint256,
    fee: uint256,
    data:  DynArray[bytes, 25000]
  ) -> bytes32: modifying # should not be constant


struct Position:
    deposit: uint256
    principal: uint256
    interestAccrued: uint256
    interestRepaid: uint256
    decimals: uint8
    token: address
    lender: address

# (uint256, uint256, uint256, uint256, uint8, address, address)

interface LineOfCredit:
    def status() -> uint256: constant
    def credits(id: bytes32) -> Position: constant
    def available(id: bytes32) -> (uint256, uint256): constant

    def addCredit(
      drate: uint128,
      frate: uint128,
      amount: uint256,
      token: address,
      lender: address
    ): modifying
    def setRates(id: bytes32 , drate: uint128, frate: uint128): modifying
    def increaseCredit(id: bytes32,  amount: uint25): modifying

    def withdraw(id: bytes32,  amount: uint25): modifying
    def close(id: bytes32): modifying


implements: [ERC20, ERC2612, ERC4626, ERC3156]
    

# constants

# @notice address to use for raw ETH when
ETH_ADDRESS: constant(address) = ZERO_ADDRESS # TODO get the address we use from chainlink lib
# @notice LineLib.STATUS.INSOLVENT
INSOLVENT_STATUS: constant(uint256) = 4
# @notice number to divide after multiplying by fee numerator variables
FEE_DENOMINATOR: constant(private(uint256)) = 10000 # TODO figure it out
# EIP712 contract name
CONTRACT_NAME: constant(private(String[13])) = "Debt DAO Pool"
# EIP712 contract version
API_VERSION: constant(private(String[5])) = "0.0.1"
# EIP712 type hash
DOMAIN_TYPE_HASH: constant(bytes32) = keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
# EIP712 permit type hash
PERMIT_TYPE_HASH: constant(bytes32) = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")


# Pool Variables

# asset manager who directs funds into investment strategies
delegate: public(address)
# minimum amount of assets that can be deposited at once. whales only, fuck plebs.
minDeposit: public(uint256)
# amount of asset held externally in lines or vaults
totalDeployed: public(uint256)
# amount of assets written down after line defaulted.
# only stores initial deposit remaining. doesnt track total owed w/ interest
impaired: public(HashMap[address, uint256])

# Fees Varaibles

# shares earned by Delegate for managing pool
delegateFees: uint256
# % (in bps) of profit that delegate keeps as incentives
performanceFeeNumerator: uint16
# % (in bps) of performance fee to give to caller for automated collections
collectorFeeNumerator: uint16
# % fee (in bps) to charge flash borrowers
flashLoanFeeNumerator: uint16

#ERC20 vars
name: immutable(public(string[50]))
symbol: immutable(public(string[10]))
# total amount of shares in pool
totalSupply: public(uint256)
# balance of pool vault shares
balances: HashMap[address, uint256]
# owner -> spender -> amount approved
allowances: HashMap[address, HashMap[address, uint256]]

# ERC4626 vars
# underlying token for pool/vault
asset: immutable(address)
# total notional amount of underlying token held in pool
totalAssets: public(uint256)

# EIP 2612 Variables
nonces: private(HashMap[address, uint256])

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

## Investing functions
@external
def addCredit(
  line: address,
  drate: uint128,
  frate: uint128,
  amount: uint256
):
  assert msg.sender == delegate
  self.totalDeployed += amount
  LineOfCredit(line).addCredit(drate, frate, amount, token, self.address)

@external
def increaseCredit(
  line: address,
  id: bytes32,
  amount: uint256
):
  assert msg.sender == delegate
  self.totalDeployed += amount
  LineOfCredit(line).increaseCredit(id, amount)

@external
def invest4626(vault: address, amount: uint256):
  assert msg.sender == delegate
  self.totalDeployed += amount
  # TODO check previewDeposit expected vs deposit actual for slippage
  ERC4626(vault).deposit(amount, self.address)

@external
def collectInterest(
  line: address,
  id: bytes32
):
  # TODO this is incorrect its a tuple not a Position Strict
  position: Position = LineOfCredit(line).available(id)

  LineOfCredit(line).withdraw(id, position.interest)
  
  self._collectInterest(interest)

@internal
def _collectInterest(interest: amount):
  # if we thought this line was INSOLVENT before. make sure we update accounting that
  if self.impaired[id] > 0:
    self.impaired[id] -= amount

  # update share price with new profits
  self._updateShares(interest, False)

  # payout fees with new share price
  self._takePerformanceFees(interest)

## Deviestment functions

@external
def reduceCredit(
  line: address,
  id: bytes32,
  amount: uint256
):
  assert msg.sender == delegate

  interest: uint256 = 0
  deposit: uint256 = 0
  # store how much interest is currently claimable
  (interest, deposit) = LineOfCredit(line).available(id)
  
  interestCollected: uint256 = 0
  if amount < interest:
    interestCollected = amount
  else:
    interestCollected = interest

  LineOfCredit(line).withdraw(id, amount)

  # LoC always sends profits before principal so will always have a value
      
  # interestCollected =  amount < interest ? amount : interest 

  self._collectInterest(interestCollected)

  # reduce principal deployed
  self.totalDeployed -= amount - interestCollected


@external
def close(vline: address, id: bytes32):
  """
    @notice
      We have to pay our own facility fee to close a position sso this is basically an emergency exit
      Use if you really want to remove liquidity from borrower fast.
      Missed interest payments are less than the principal you think you'll lose
  """
  assert msg.sender == delegate
  position: Position = ILineOfCredit(line).credits(id)
  
  # must approve line to use our tokens so we can repay our own interest
  ERC20(asset).approve(line, MAX_UINT256)
  assert ILineOfCredit(line).close(id)
  
  # reduce deployed by withdrawn principal
  self.totalDeployed -= position.deposit

  # TODO need to know how much interest we got in excess of the interest we paid (if any)


@external
def divest4626(vault: address, amount: uint256):
  assert msg.sender == delegate
  self.totalDeployed -= amount
  # TODO check previewWithdraw expected vs withdraw actual for slippage
  ERC4626(vault).withdraw(amount, self.address)
  # TODO how do we tell what is principal and what is profit??? need to update totalAssets with yield

  # delegate doesnt earn fees on 4626 strategies to incentivize line investment


@external
def impair(line: address, id: bytes32):
  """
    @notice     - allows Delegate to markdown the value of a defaulted loan reducing vault share price.
    @param line - line of credit contract to call
    @param id   - credit position on line controlled by this pool 
  """
  assert LineOfCredit(line).status() == INSOLVENT_STATUS

  position: Position = LineOfCredit(line).credits(id)

  claimable: uint256 = interestPaid + (deposit - principal) # all funds left in line
  impaired[line] += principal  # write down lost principal
  
  diff: uint266 = 0
  if claimable > 0:
    LineOfCredit(line).withdraw(claimable)
    diff = principal - interestPaid  # reduce diff by recovered funds

  # TODO take profermanceFee from delegate to offset impairment and reduce diff
  # TODO currently callable by anyone. Should we give % of delegates fees to caller for impairing?

  self._updateShares(diff, True)

## Maitainence functions

@external
def setRates(
  line: address,
  id: bytes32,
  drate: uint128,
  frate: uint128,
):
  assert msg.sender == delegate
  LineOfCredit(line).setRates(id, drate, frate)


# 4626 action functions
@nonreentrant("mutex")
@external
def deposit(assets: uint256, to: address):
  """
    adds assets
  """
  self._deposit(amount / self._getSharePrice(), amount, to)

@nonreentrant("mutex")
@external
def mint(shares: uint256, to: address):
  """
    adds shares
  """
  self._deposit(shares, amount * self._getSharePrice(), to)

@nonreentrant("mutex")
@external
def withdraw(
  amount: uint256,
  receiver: address,
  owner: address
):
  assert msg.sender == owner or allowances[owner][msg.sender] >= amount
  allowances[owner][msg.sender] -= amount
  self._withdraw(amount / self._getSharePrice(), amount, to)

@nonreentrant("mutex")
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
  """
    adds shares to a user after depositing into vault
    priviliged internal func
  """
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
  assert assets <= self._getMaxLiquidAssets()

  totalAssets -= amount
  balances[to] -= shares
  assert ERC20(asset).transfer(to, amount)
  # emit withdraw

@internal
def _takePerformanceFees(interestEarned: uint256):
  """
    @notice takes total profits earned and takes fees for delegate and compounder
    @dev fees are stored as shares but input/ouput assets
    @return total amount of assets taken as fees
  """
  if performanceFeeNumerator == 0:
    return 0

  totalFees: uint256 = interest * performanceFeeNumerator / FEE_DENOMINATOR
  collectorFee: uint256 = 0
  if (
    collectorFeeNumerator != 0 or
    msg.sender != delegate
  ):
    collectorFee = totalFees * collectorFeeNumerator / FEE_DENOMINATOR

  # caller gets collector fees in raw asset for easier mev
  ERC20(asset).transfer(msg.sender, collectorFee)
  totalAssets -= collectorFee

  # delegate gets performance fee.
  # Not stored in balance so we can differentiate fees earned vs their won deposits, letting us slash fees on impariment.
  # earn fees in shares, not raw asset, so profit is vested like other users
  sharePrice = self._getSharePrice()
  delegateFee += (totalFees - collectorFee) / sharePrice
  self.balances[delegate] += delegateFee
  self.delegateFees += delegateFee

  # inflate supply to reduce user share price
  self.totalSupply += delegateFee
  
  return totalFees

# ERC20 action functions

@external
def transfer(to: address, amount: uint256):
  self.balance[msg.sender] -= amount
  self.balance[to] -= amount
  # TODO log event
  return True


@external
def transferFrom(sender: address, recipient: address, amount: uint256):
  assert self.allowances[sender][msg.sender] >= amount
  self.allowances[sender][msg.sender] -= amount
  self.balance[sender] -= amount
  self.balance[recipient] -= amount
  # TODO log event
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
  if available > total:
      return total
  else:
      return available



# TODO ERC2612 permit, nonce, DOMAIN _SEPERATOR
# EIP712 domain separator
@view
@internal
def domain_separator() -> bytes32:
  keccak256(
    concat(
        DOMAIN_TYPE_HASH,
        keccak256(CONTRACT_NAME),
        keccak256(API_VERSION),
        chain.id,
        self.address
  )
)

# ERC 3156 Flash Loan functions
@view
@external
def maxFlashLoan(token: address) -> uint256:
  if token != asset:
    return 0
  else:
    return self._getMaxLiquidAssets()

@view
@internal
def _getFlashFee(token: address, amount: uint256) -> uint256:
  if flashLoanFeeNumerator == 0:
    return 0
  else:
    return self._getMaxLiquidAssets() * flashLoanFeeNumerator / FEE_DENOMINATOR

@view
@external
def flashFee(token: address, amount: uint256) -> uint256:
  assert token == self.asset
  return self_getFlashFee()

@nonreentrant("mutex")
@external
def flashLoan(
    receiver: address,
    token: address,
    amount: uint256,
    data: DynArray[bytes, 25000]
) -> bool:
  assert amount <= self._getMaxLiquidAssets()

  # give them the flashloan
  ERC20(asset).transfer(msg.sender, amount)

  fee = self_getFlashFee()
  # ensure they can receive flash loan
  assert IERC3156FlashBorrower(receiver).onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan")
  
  # receive payment
  ERC20(asset).transferFrom(msg.sender, self, amount + fee)

  self._updateShares(fee)

  return True
# EIP712 permit functionality

# domain separator
@view
@external
def DOMAIN_SEPARATOR() -> bytes32:
  self.domain_separator()


@external
def permit(owner: address, spender: address, amount: uint256, expiry: uint256, signature: Bytes[65]) -> bool:
    """
    @notice
        Approves spender by owner's signature to expend owner's tokens.
        See https://eips.ethereum.org/EIPS/eip-2612.
        Stolen from Yearn Vault code
        https://github.com/yearn/yearn-vaults/blob/74364b2c33bd0ee009ece975c157f065b592eeaf/contracts/Vault.vy#L765-L806
    @param owner The address which is a source of funds and has signed the Permit.
    @param spender The address which is allowed to spend the funds.
    @param amount The amount of tokens to be spent.
    @param expiry The timestamp after which the Permit is no longer valid.
    @param signature A valid secp256k1 signature of Permit by owner encoded as r, s, v.
    @return True, if transaction completes successfully
    """
    assert owner != ZERO_ADDRESS  # dev: invalid owner
    assert expiry >= block.timestamp  # dev: permit expired
    
    nonce: uint256 = self.nonces[owner]
    digest: bytes32 = keccak256(
        concat(
            b'\x19\x01',
            self.domain_separator(),
            keccak256(
                concat(
                    PERMIT_TYPE_HASH,
                    convert(owner, bytes32),
                    convert(spender, bytes32),
                    convert(amount, bytes32),
                    convert(nonce, bytes32),
                    convert(expiry, bytes32),
                )
            )
        )
    )
    # NOTE: signature is packed as r, s, v
    r: uint256 = convert(slice(signature, 0, 32), uint256)
    s: uint256 = convert(slice(signature, 32, 32), uint256)
    v: uint256 = convert(slice(signature, 64, 1), uint256)
    assert ecrecover(digest, v, r, s) == owner  # dev: invalid signature
    self.allowance[owner][spender] = amount
    self.nonces[owner] = nonce + 1
    log Approval(owner, spender, amount)
    return True


# TODO ERC3614 flash loans


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


@pure
@external
def apiVersion() -> String[28]:
    """
    @notice
        Used to track the deployed version of this contract. In practice you
        can use this version number to compare with Debt DAO's GitHub and
        determine which version of the source matches this deployed contract.
    @dev
        All strategies must have an `apiVersion()` that matches the Vault's
        `API_VERSION`.
    @return API_VERSION which holds the current version of this contract.
    """
    return API_VERSION

# ERC20 Events
# ERC4626 Events
