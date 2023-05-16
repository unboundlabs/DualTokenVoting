import {addDeployedContract} from '../../utils/helpers';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

const name = 'DualTokenVotingSetup';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  console.log(`${name}`);

  const {deployments, network, getNamedAccounts} = hre;
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();

  const TokenChecker = await deploy("TokenChecker", {
    from: deployer
  });

  const ERC20WrapperHelper = await deploy("ERC20WrapperHelper", {
    from: deployer,
    args: [],
    log: true,
    libraries: {
      TokenChecker: TokenChecker.address
    }
  })

  const NTTokenHelper = await deploy("NTTokenHelper", {
    from: deployer,
    args: [],
    log: true,
    libraries: {
      TokenChecker: TokenChecker.address
    }
  })

  const ERC20TokenHelper = await deploy("ERC20TokenHelper", {
    from: deployer,
    args: [ERC20WrapperHelper.address],
    log: true,
    libraries: {
      TokenChecker: TokenChecker.address
    }
  })

  const result = await deploy('DualTokenVotingSetup', {
    from: deployer,
    args: [ERC20TokenHelper.address, NTTokenHelper.address],
    log: true,
    libraries: {
      TokenChecker: TokenChecker.address
    }
  });

  addDeployedContract(network.name, name, result.address);
};

export default func;
func.tags = [name];
