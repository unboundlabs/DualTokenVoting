import {
  PluginRepo,
  DualTokenVotingSetup,
  DualTokenVotingSetup__factory,
} from '../../typechain';
import {getDeployedContracts, osxContracts, networkNameMapping} from '../../utils/helpers';
import {toHex} from '../../utils/ipfs-upload';
import {PluginRepoRegistry__factory} from '@aragon/osx-ethers';
import {PluginRepoRegistry} from '@aragon/osx-ethers';
import {PluginRepo__factory} from '@aragon/osx-ethers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {deployments, ethers, network} from 'hardhat';

let signers: SignerWithAddress[];
let repoRegistry: PluginRepoRegistry;
let dualTokenVotingRepo: PluginRepo;

let setupR1B1: DualTokenVotingSetup;

describe.only('DualVotingToken Deployment', function () {
  before(async () => {
    const hardhatForkNetwork = process.env.HARDHAT_FORK_NETWORK
      ? process.env.HARDHAT_FORK_NETWORK
      : 'mainnet';

    signers = await ethers.getSigners();
     // deployment should be empty
     expect(await deployments.all()).to.be.empty;

     // // deploy framework
     await deployments.fixture();

    // plugin repo registry
    repoRegistry = PluginRepoRegistry__factory.connect(
      osxContracts[networkNameMapping[hardhatForkNetwork]]['PluginRepoRegistry'],
      signers[0]
    );
    // This assumes that the deployAll wrote the `PluginRepo` entry to the file.
    dualTokenVotingRepo = PluginRepo__factory.connect(
      getDeployedContracts()[network.name]['PluginRepo'],
      signers[0]
    );

    setupR1B1 = DualTokenVotingSetup__factory.connect(
      (await deployments.get('DualTokenVotingSetup')).address,
      signers[0]
    );
  });

  it('creates the repo', async () => {
    expect(await repoRegistry.entries(dualTokenVotingRepo.address)).to.be
      .true;
  });

  it('registerd the dualTokenVotingRepo', async () => {
    const results = await dualTokenVotingRepo['getVersion((uint8,uint16))'](
      {
        release: 1,
        build: 1,
      }
    );

    expect(results.pluginSetup).to.equal(setupR1B1.address);
  });

  it('makes the deployer the repo maintainer', async () => {
    expect(
      await dualTokenVotingRepo.isGranted(
        dualTokenVotingRepo.address,
        signers[0].address,
        ethers.utils.id('ROOT_PERMISSION'),
        ethers.constants.AddressZero
      )
    ).to.be.true;

    expect(
      await dualTokenVotingRepo.isGranted(
        dualTokenVotingRepo.address,
        signers[0].address,
        ethers.utils.id('UPGRADE_REPO_PERMISSION'),
        ethers.constants.AddressZero
      )
    ).to.be.true;

    expect(
      await dualTokenVotingRepo.isGranted(
        dualTokenVotingRepo.address,
        signers[0].address,
        ethers.utils.id('MAINTAINER_PERMISSION'),
        ethers.constants.AddressZero
      )
    ).to.be.true;
  });
});
