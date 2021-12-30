# import IERC20, SafeERC20
# import Ownable

struct RevenueContract:
  token: address
  ownerSplit: uint256 # % to Owner, rest to Treasury
  totalEscrowed: uint256
  claimFunction: Bytes[4]

revenueContracts: public(HashMap[address, RevenueContract])
whitelistedFunctions: public(HashMap[Bytes[4], bool]) # allowd by operator on all revenue contracts

event AddRevenueSpigot:
  contract: indexed(address)
  token: address
  ownerSplit: uint256

event RemoveRevenueSpigot:
  contract: indexed(address)
  token: address

event UpdateWhitelistFunction:
  function: indexed(Bytes[4])
  allowed: indexed(bool)

event ClaimRevenue:
  contract: address
  token: indexed(address)
  amount: indexed(uint256)
  escrowed: uint256

event ClaimEscrow:
  owner: address
  contract: address
  token: indexed(address)
  amount: indexed(uint256)

### Stakeholder variables
owner: public(address)
operator: public(address)
treasury: public(address)

event UpdateOwner:
  newOwner: indexed(address)

event UpdateOperator:
  newOperator: indexed(address)
  
event UpdateTreasury:
  newTreasury: indexed(address)


@external
def initialize(
  owner: address,
  operator: address,
  treasury: address,
  contracts: address[10],
  settings: RevenueContract[10],
  whitelist: Bytes[40]
):
  """
  @dev configure data for contract owners and initial revenue contracts.
       Owner/operator/treasury can all be the same address
  @param

  """
  for addy in [owner, operator, treasury]:
    assert self != addy
    assert ZERO_ADDRESS != addy

  self.owner = owner
  self.operator = operator
  self.treasury = treasury
  
  for i in range( len(contracts) ):
    # TODO replace with self._addSpigot
    assert settings[i].claimFunction != convert(0, Bytes[4]) # 0x0 works?
    revenueContracts[ contracts[i] ] = settings[i]
    log AddRevenueSpigot(contracts[i], settings[i].token, settings[i].ownerSplit)
  
  for i in range( len(whitelist) / 4 ):
    func: Bytes4 = slice(whitelist, i*4, i*4 + 4)
    whitelistedFunctions[func] = True
    log UpdateWhitelistFunction(func, True)



##########################
# Claimoooor
##########################
@external
def claimRevenue(revenueContract: address, data: Bytes[1000]):
  """
  @dev
      Calls revenueContract on preconfigured claim function 
      Only used for pull payments. If revenue is sent directly to Spigot use `updateRevenueBalance`
  @param revenueContract
      Revenue generating contract to divert funds through
  @param data
      Transaction data, including claimFunction, to properly claim revenue on revenueContract
  """

  revenueToken: address = revenueContracts[revenueContract].token
  currentBalance: uint256 = IERC20(revenueToken).balanceOf(self)
  raw_call(
    revenueContract,
    concat(
      revenueContracts[revenueContract].claimFunction,
      data
    )
  )
  
  claimedAmount: uint256 = IERC20(revenueToken).balanceOf(self) - currentBalance
  escrowedAmount: uint256 = claimedAmount / revenueContracts[revenueContract].ownerSplit
  
  # divert claimed revenue to escrow and treasury
  revenueContracts[revenueContract].totalEscrowed += escrowedAmount
  success: bool = IERC20(revenueToken).transfer(self, treasury, claimedAmount - escrowedAmount)
  assert success, "Treasury revenue payment failed"
  
  log ClaimRevenue(revenueContract, revenueToken, claimedAmount, escrowedAmount)

@external
def updateRevenueBalance(revenueContract: address):

  """
  @dev
      Only used for push payments. If revenueContract needs to be called to claim use `claimRevenue`
  @param revenueContract
      Preconfigured Revenue generating contract to divert funds through
  """
  revenueToken: address = revenueContracts[revenueContract].token
  claimedAmount: uint256 = IERC20(revenueToken).balanceOf(self)
  escrowedAmount: uint256 = claimedAmount / revenueContracts[revenueContract].ownerSplit

  revenueContracts[revenueContract].totalEscrowed += escrowedAmount
  success: bool = IERC20(revenueToken).transfer(self, treasury, claimedAmount - escrowedAmount)
  assert success, "Treasury revenue stream failed"

  log ClaimRevenue(revenueContract, revenueToken, claimedAmount, escrowedAmount)
  
@external
def claimEscrow(revenueContract: address):
  """
    @dev configure data for contract owners and initial revenue contracts.
        Owner/operator/treasury can all be the same address
    @param revenueContract
        Preconfigured revenue generating contract that has sent tokens to this Spigot contract

  """
  assert msg.sender == owner
  success: bool = IERC20(revenueContracts[revenueContract].token).transfer(self, owner, revenueContracts[revenueContract].totalEscrowed)
  assert success, "Escrow claim failed"
  log ClaimEscrow(owner, revenueContract,revenueContracts[revenueContract].token, revenueContracts[revenueContract].totalEscrowed)
  revenueContracts[revenueContract].totalEscrowed = 0

##########################
# Maintainooor
##########################

@external
def addRevenueSpigot():
    assert msg.sender == operator

@external
def updateOwner(newOwner: address):
    assert msg.sender == owner
    assert newOwner != ZERO_ADDRESS
    owner = newOwner
    log updateOwner(newOwner)

@external
def updateOperator(newOperator: address):
    assert msg.sender == operator
    assert newOperator != ZERO_ADDRESS
    operator = newOperator
    log updateOwner(newOperator)

@external
def updateTreasury(newTreasury: address):
    assert msg.sender in [treasury, operator]
    assert newTreasury != ZERO_ADDRESS
    treasury = newTreasury
    log updateOwner(newTreasury)

##########################
#   // *ring* *ring*
#   // OPERATOOOR 
#   // OPERATOOOR
##########################
@external
def operate(revenueContract: address, ethVal: uint256, data: bytes):
  return self._operate(revenueContract, ethVal, data)

@internal
def _operate(revenueContract: address, ethVal: uint256, data: bytes):
  assert msg.sender == self.operator
  function: Bytes[4] = slice(data, 0, 4) # data[0:4] syntax in vyper???
  assert whitelistedFunctions(function), "Unauthorized Operator action"

  response: Bytes[32] = raw_call(revenueContract, data, max_outsize= Bytes[32], value=ethVal)
  # @dev might need to update max_out based on integration tests
  return response

