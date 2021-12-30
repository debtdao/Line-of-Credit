// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { default: hre, ethers } = require("hardhat");

async function verifyContract(name, address, params) {
    console.log('Verifying contract ', name);
    try {
        await hre.run('verify:verify', {
            address: address,
            constructorArguments: params,
        });
        console.log('Successfully verified ', name);
    } catch (error) {
        const alreadyVerified = error.message.includes('Contract source code already verified') ||
                                error.message.includes('Already Verified')
        if (alreadyVerified) {
            console.log(name, ' already verified, skipping.');
        } else {
            console.log('Error verifying ', name);
            console.error(error);
            throw error;
        }
    }
}


async function main() {
    const deploydContracts = {}
    const toWei = ethers.utils.bigNumberify;

    const debtTeamMultisig = "0xA097856Ef35D368184DE4c3771E7F363B5Cb01E5";
    const debtTreasury = "0xdebt";
    const ohmTreasury = "0xohm";
    const initialDebtSupply = 10**11;
    const initialCreditSupply = 10**7;
    const secondsPerYear = 60 * 60 * 24 * 364.25

    // get contracts
    const CreditToken = await hre.ethers.getContractFactory("CreditToken");
    const DebtToken = await hre.ethers.getContractFactory("DebtToken");
    // deploy contracts
    const CREDIT = await CreditToken.deploy(toWei(initialCreditSupply)); // initial 10 million dollar global credit limit
    const DEBT = await DebtToken.deploy(toWei(initialDebtSupply)); // initial 10 billion supply

    // setup initial CREDIT configuration
    await CREDIT.deployed();
    verifyContract("CREDIT", CREDIT.address, [toWei(initialCreditSupply)]);
    console.log("CREDIT deployed to: ", CREDIT.address);

    CREDIT.updateMinter(debtTeamMultisig, true);
    CREDIT.transferOwnership(debtTeamMultisig);

    await DEBT.deployed();
    console.log("DEBT deployed to: ", DEBT.address);
    verifyContract("DEBT", DEBT.address, [toWei(initialDebtSupply)]);

    // 3.3% to OHM approved in partnership agreement
    const ohmTreasuryAmount = initialDebtSupply * 0.033;
    // 61.7% = 36.7% for community treasury + 15% parnterships + 10% strategic raise
    const debtTreasuryAmount = initialDebtSupply * 0.617;
    // 20% to team
    const debtTeamAmount = initialDebtSupply * 0.2;
    // 15% for LBP and OP
    const tokenLaunchAmount = initialDebtSupply * 0.15;

    // distribute inital funds
    DEBT.transfer(debtTreasury, toWei(tokenLaunchAmount));
    console.log("Token launch supply sent to treasury: ", tokenLaunchAmount, debtTreasury);

    // Start DEBT token vesting
    const VestingContract = await hre.ethers.getContractFactory("TokenVesting");

    const ohmVestingParams = [
        DEBT.address,
        ohmTreasury,
        ethers.constants.AddressZero, // no clawback
        toWei(ohmTreasuryAmount),
        Date.now() / 1000,
        0,                      // no cliff
        secondsPerYear * 1.5
    ]
    const ohmVesting = await VestingContract.deploy(ohmVestingParams);

    const treasuryVestingPrarms = [
        DEBT.address,
        debtTreausry,
        ethers.constants.AddressZero, // no clawback
        toWei(debtTreasuryAmount),
        Date.now() / 1000,
        0,                   // no cliff
        secondsPerYear * 3
    ]
    const debtTreasuryVesting = await VestingContract.deploy(debtTreasuryVesting);
    
    const teamVestingPrarms = [
        DEBT.address,
        debtTeamMultisig,
        debtTreasury,
        toWei(debtTeamAmount),
        Date.now() / 1000,
        secondsPerYear,
        secondsPerYear * 4
    ]
    const teamVesting = await VestingContract.deploy(teamVestingPrarms);
    
    await Promise.all([ohmVesting.deployed, debtTreasuryVesting.deployed, teamVesting.deployed])
    let vestingVerifications = [
        verifyContract("Olympus Vesting", ohmVesting.address, ohmVestingParams),
        verifyContract("Treasury Vesting", teamVesting.address, teamVestingParams),
        verifyContract("Team Vesting", treasuryVesting.address, treasuryVestingParams)
    ];

    await DEBT.transferOwnership(debtTreasury);
    console.log('DEBT ownership transferred to treasury: ', debtTreasury);    

    await Promise.all(vestingVerifications);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
