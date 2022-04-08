import { LoanLib } from "../utils/LoanLib.sol";

interface IInterestRate {
  function accrueInterest(
    bytes32 positionId, 
    uint256 amount, 
    LoanLib.STATUS currentStatus
  ) external returns(uint256);
}
