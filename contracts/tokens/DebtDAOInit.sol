// pragma solidity ^0.8.9;

// import { DebtToken } from "./DebtToken.sol";
// import { CreditToken } from "./CreditToken.sol";
// import { TokenVesting } from "./TokenVesting.sol";


// contract DebtDAOInit {

//     address constant debtGovernance = 0xA097856Ef35D368184DE4c3771E7F363B5Cb01E5; // debtdao.eth
//     address constant debtTreasury = address(0); // TODO
//     address constant ohmTreasury = address(0); // TODO


//     constructor(uint256 creditLimit, uint256 debtSupply) {
//         // Deploy synthetic dollar CREDIT token
//         CreditToken credit = new CreditToken(creditLimit);
//         // Allow core team to distribute credit to borrowers
//         credit.updateMinter(debtGovernance, true);
//         // Setup complete. Handoff CREDIT control to Debt DAO core
//         credit.transferOwnership(debtGovernance);

//         // Deploy Debt DAO governance token
//         DebtToken debt = new DebtToken(debtSupply);

//         // 3.33% to OHM approved in partnership agreement
//         uint256 ohmTreasuryAmount = debtSupply.div(33.333333);
//         // 61.7% = 36.7% for community treasury + 15% parnterships + 10% strategic raise
//         uint256 debtTreasuryAmount = debtSupply.div(1.620745542949757);
//         // 20% to team
//         uint256 debtTeamAmount = debtSupply.div(5);
//         // 15% for LBP and OP
//         uint256 debtLaunchAmount = debtSupply.div(6.66666667);
        
//         require(debtSupply >= ohmTreasuryAmount.add(debtTreasuryAmount).add(debtTeamAmount).add(debtLaunchAmount));

//         address ohmTreasuryVesting = new TokenVesting(
//             debt,
//             ohmTreasury,
//             debtTreasury,
//             ohmTreasuryAmount,
//             now,
//             0,
//             1.5 years
//         );
//         require(debt.transfer(ohmTreasuryVesting, ohmTreasuryAmount), "DDInit: failed transfering DEBT");

//         address debtTreasuryVesting = new TokenVesting(
//             debt,
//             debtTreasury,
//             debtTreasury,
//             debtTreasuryAmount,
//             now,
//             0,
//             3 years
//         );
//         require(debt.transfer(debtTreasuryVesting, debtTreasuryAmount), "DDInit: failed transfering DEBT");

//         // TODO add personal allocations?
//         address debtTeamVesting = new TokenVesting(
//             debt,
//             debtGovernance,
//             debtTreasury,
//             debtTeamAmount,
//             now,
//             1 years,
//             4 years
//         );
//         require(debt.transfer(debtTeamVesting, debtTeamAmount), "DDInit: failed transfering DEBT");

//         // LBP and OP funds immediately available
//         // Might be slightly off from 15% bc rounding in earlier calculations
//         require(debt.transfer(debtTreasury, debt.balanceOf(address(this))), "DDInit: failed transfering DEBT");

//         // Setup complete. Handoff DEBT control to community treasury
//         debt.transferOwnership(debtTreasury);

//         selfdestruct(debtTreasury); // RIP thank you for your service ser
//     }
// }
