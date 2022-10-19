import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction} from 'hardhat-deploy/types';
import { utils } from "ethers";
import { ethers } from 'hardhat';
const toWei = (n: number) => utils.formatUnits(n, "wei");

const oneDayInSec = 60*60*24;
const deployTestLine: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  getChainId,
  getUnnamedAccounts,
}) {
  const { deploy, execute } = deployments;
  console.log('deployments', deployments);
  const { deployer } = await getNamedAccounts();
  const [debf,__,___] = await getUnnamedAccounts();
  const from = deployer || debf;
  console.log('accounts', deployer, debf, from);
  // TODO abstract token and oracle deployment into separate scripts as dependencies
  const token = await deploy('RevenueToken', { from });

  console.log('deploy token', token.address);
  
  console.log('Deploying Oracle with pricing for token and ETH...');
  const oracle = await deploy('SimpleOracle', {
    from,
    args: [token.address, "0x0000000000000000000000000000000000000000"]
  });
  console.log('Oracle Deployed', oracle.address);


  
  console.log('Deploying Libraries...');
  const LoanLib = await deploy('LoanLib', { from });
  const CreditLib = await deploy('CreditLib', { from });
  const CreditListLib = await deploy('CreditListLib', { from });

  const SpigotedLoanLib = await deploy('SpigotedLoanLib', { from });

  console.log('Libraries deployed', LoanLib.address, CreditLib.address, CreditListLib.address, SpigotedLoanLib.address);

  const spigot = await deploy('Spigot', {
    from,
    args: [
      from,
      from,
      from
    ]

  })

  console.log('Spigot Deployed', spigot.address)

  const escrow = await deploy('Escrow', {
    from,
    libraries: {
      'CreditLib': CreditLib.address,
    },
    args: [
      0,
      oracle.address,
      from,
      from
    ]

  })
  console.log('Escrow Deployed', escrow.address)
  
  console.log('Deploying Line of Credit for token...');
  const line = await deploy('SecuredLoan', {
    from,
    libraries: {
      'LoanLib': LoanLib.address,
      'CreditLib': CreditLib.address,
      'CreditListLib': CreditListLib.address,
      'SpigotedLoanLib':SpigotedLoanLib.address
    },
    args: [
      oracle.address,
      from,             // arbiter
      from,             // borrower
      oracle.address,   // no swaps
      spigot.address,   // spigot
      escrow.address,   // escrow
      oneDayInSec * 3,  // ttl (seconds)
      0                 // defaultSplit
    ],
  });
  console.log('deploy line', line);

  if(token.newlyDeployed) {
    console.log('Token just deployed. Minting to deployer...');

    const toToken = {from, to: token.address}

    const mintToken = () => execute(
      'RevenueToken',
      toToken,
      'mint',
      [5]
    )

    const approveToken = () => execute(
      'RevenueToken',
      toToken,
      'approve',
      [line.address, toWei(100)]
    )

    await Promise.all([mintToken(), approveToken()])
    
    //await token.mint(deployer, 5); // mint so we can borrow/lend/collateralize
    console.log('Token just deployed. Approving LoC...');
    //await token.approve(line.address, toWei(100))
  }

  const toSpigot = { from, to: spigot.address}

  const changeSpigotOwner = () => execute(
    'Spigot',
    toSpigot,
    'updateOwner',
    [line.address]
  )

  const toEscrow = {from, to: escrow.address}

  const changeEscrowOwner = () => execute(
    'Escrow',
    toEscrow,
    'updateLoan',
    [line.address]
  )

  

  await Promise.all([changeEscrowOwner(), changeSpigotOwner()])

  
  

  const toLine = { from, to: line.address }

  const initLoan = () => execute(
    'SecuredLoan',
    toLine,
    'init'
  )

  const enableCollateral = () => execute(
    'Escrow',
    toEscrow,
    'enableCollateral',
    [token.address]
  )

  const addCollateral = () => execute(
    'Escrow',
    toEscrow,
    'addCollateral',
    [1]
  )

  await Promise.all([initLoan(), enableCollateral(), addCollateral()])

  // add line of credit
  const addCredit = () => execute(
    'SecuredLoan',
    toLine,
    'addCredit',
    // 10%, 5%
    [1000, 500, 10, token.address, deployer]
  );

  console.log('Adding LoC for token to deployer...');
  const res = await Promise.all([addCredit(), addCredit()]);
  
  console.log('Borrowing as deployer...');
  console.log(res)
  await execute(
    'SecuredLoan',
    toLine,
    'borrow',
    // id, amount
    [res[1], 5] // literally only 5, not 5 ether. Gorli ETH = mainnet ETH kekek
  );
};

// TODO setup scripts for initialization
// module.exports.dependencies = ['TestTokens', 'TestOracle'];
export default deployTestLine;
