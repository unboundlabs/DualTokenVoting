import {expect} from 'chai';
import {ethers} from 'hardhat';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';

import {ERC20, DualTokenVotingSetup, DualTokenVotingSetup__factory, ERC20__factory, ERC721__factory, ERC721, NTToken__factory, ERC721Mock__factory, ERC20WrapperHelper__factory, ERC20WrapperHelper, ERC20TokenHelper, ERC20TokenHelper__factory, NTTokenHelper, NTTokenHelper__factory, TokenChecker, TokenChecker__factory} from '../../typechain';
import {deployNewDAO} from '../../utils/dao';
import {getInterfaceID} from '../../utils/interfaces';
import {Operation} from '../helpers/types';
import metadata from '../../contracts/release1/build1/build-metadata.json';

import {
  VotingSettings,
  VotingMode,
  pctToRatio,
  ONE_HOUR,
} from '../../utils/voting';

let defaultData: any;
let defaultVotingSettings: VotingSettings;
let defaultPowerTokenSettings: {addr: string; name: string; symbol: string};
let defaultMemberTokenSettings: {addr: string; name: string; symbol: string};
let defaultMintSettings: {receivers: string[]; amounts: number[]};

const abiCoder = ethers.utils.defaultAbiCoder;
const AddressZero = ethers.constants.AddressZero;
const EMPTY_DATA = '0x';

const prepareInstallationDataTypes =
  metadata.pluginSetupABI.prepareInstallation;

const tokenName = 'name';
const tokenSymbol = 'symbol';
const merkleMintToAddressArray = [ethers.Wallet.createRandom().address];
const merkleMintToAmountArray = [1];

// Permissions
const UPDATE_VOTING_SETTINGS_PERMISSION_ID = ethers.utils.id(
  'UPDATE_VOTING_SETTINGS_PERMISSION'
);
const UPGRADE_PERMISSION_ID = ethers.utils.id('UPGRADE_PLUGIN_PERMISSION');
const EXECUTE_PERMISSION_ID = ethers.utils.id('EXECUTE_PERMISSION');
const MINT_PERMISSION_ID = ethers.utils.id('MINT_PERMISSION');
const NTT_MINT_PERMISSION_ID = ethers.utils.id('NTT_MINT_PERMISSION');

describe.only('DualTokenVotingSetup', function () {
  let signers: SignerWithAddress[];
  let dualTokenVotingSetup: DualTokenVotingSetup;
  let eRC20WrapperHelper: ERC20WrapperHelper;
  let eRC20TokenHelper: ERC20TokenHelper;
  let nTTokenHelper: NTTokenHelper;
  let implementationAddress: string;
  let targetDao: any;
  let erc20Token: ERC20;
  let erc721Token: ERC721;

  before(async () => {
    signers = await ethers.getSigners();
    targetDao = await deployNewDAO(signers[0].address);

    defaultVotingSettings = {
      votingMode: VotingMode.EarlyExecution,
      supportThreshold: pctToRatio(50),
      minParticipation: pctToRatio(20),
      minDuration: ONE_HOUR,
      minProposerVotingPower: 0,
    };
    defaultPowerTokenSettings = {addr: AddressZero, name: '', symbol: ''};
    defaultMemberTokenSettings = {addr: AddressZero, name: '', symbol: ''};
    defaultMintSettings = {receivers: [], amounts: []};

    // Library deployment
    const lib = await ethers.getContractFactory("TokenChecker") as TokenChecker__factory;
    const libInstance = await lib.deploy();
    await libInstance.deployed();

    const ERC20WrapperHelper = await ethers.getContractFactory(
      'ERC20WrapperHelper'
    ) as ERC20WrapperHelper__factory;

    const NTTokenHelper = await ethers.getContractFactory(
      'NTTokenHelper',
      {
        libraries: {
          TokenChecker: libInstance.address
      }}
    ) as NTTokenHelper__factory;

    const ERC20TokenHelper = await ethers.getContractFactory(
      'ERC20TokenHelper',
      {
        libraries: {
          TokenChecker: libInstance.address
      }}
    ) as ERC20TokenHelper__factory;

    const DualTokenVotingSetup = await ethers.getContractFactory(
      'DualTokenVotingSetup',
      {
        libraries: {
          TokenChecker: libInstance.address
      }}
    ) as DualTokenVotingSetup__factory;

    eRC20WrapperHelper = await ERC20WrapperHelper.deploy();

    eRC20TokenHelper = await ERC20TokenHelper.deploy(eRC20WrapperHelper.address);

    nTTokenHelper = await NTTokenHelper.deploy();

    dualTokenVotingSetup = await DualTokenVotingSetup.deploy(eRC20TokenHelper.address, nTTokenHelper.address);

    implementationAddress = await dualTokenVotingSetup.implementation();

    const ERC20Token = await ethers.getContractFactory('ERC20') as ERC20__factory;
    erc20Token = await ERC20Token.deploy(tokenName, tokenSymbol);

    const ERC721Token = await ethers.getContractFactory('ERC721') as ERC721__factory;
    erc721Token = await ERC721Token.deploy("Member", "MEM");

    defaultData = abiCoder.encode(prepareInstallationDataTypes, [
      Object.values(defaultVotingSettings),
      Object.values(defaultPowerTokenSettings),
      Object.values(defaultMemberTokenSettings),
      Object.values(defaultMintSettings),
    ]);
  });

  describe('prepareInstallation', async () => {
    it('fails if data is empty, or not of minimum length', async () => {
      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, EMPTY_DATA)
      ).to.be.reverted;

      await expect(
        dualTokenVotingSetup.prepareInstallation(
          targetDao.address,
          defaultData.substring(0, defaultData.length - 2)
        )
      ).to.be.reverted;

      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, defaultData)
      ).not.to.be.reverted;
    });

    it('fails if `MintSettings` arrays do not have the same length', async () => {
      const receivers: string[] = [AddressZero];
      const amounts: number[] = [];
      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        Object.values(defaultPowerTokenSettings),
        Object.values(defaultMemberTokenSettings),
        {receivers: receivers, amounts: amounts},
      ]);

      const nonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce,
      });

      const GovernanceERC20 = await ethers.getContractFactory(
        'GovernanceERC20'
      );

      const govToken = GovernanceERC20.attach(anticipatedPluginAddress);

      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, data)
      )
        .to.be.revertedWithCustomError(
          govToken,
          'MintSettingsArrayLengthMismatch'
        )
        .withArgs(1, 0);
    });

    it('fails if passed token address is not a contract', async () => {
      const tokenAddress = signers[0].address;
      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [tokenAddress, '', ''],
        [tokenAddress, '', ''],
        Object.values(defaultMintSettings),
      ]);

      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, data)
      )
        .to.be.revertedWithCustomError(eRC20TokenHelper, 'TokenNotContract')
        .withArgs(tokenAddress);
    });

    it('fails if passed token address is not ERC20', async () => {
      const tokenAddress = implementationAddress;
      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [tokenAddress, '', ''],
        [tokenAddress, '', ''],
        Object.values(defaultMintSettings),
      ]);

      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, data)
      )
        .to.be.revertedWithCustomError(eRC20TokenHelper, 'TokenNotERC20')
        .withArgs(tokenAddress);
    });

    it('fails if passed member token address is not supported', async () => {
      const tokenAddress = implementationAddress;
      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [erc20Token.address, '', ''],
        [tokenAddress, '', ''],
        Object.values(defaultMintSettings),
      ]);

      await expect(
        dualTokenVotingSetup.prepareInstallation(targetDao.address, data)
      )
        .to.be.revertedWithCustomError(nTTokenHelper, 'MemberTokenNotSupported')
        .withArgs(tokenAddress);
    });

    it('correctly returns plugin, helpers and permissions, when an ERC20 token address is supplied and membership token is not supplied', async () => {
      const dtvsNonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );

      const whNonce = await ethers.provider.getTransactionCount(
        eRC20WrapperHelper.address
      );
      const thNonce = await ethers.provider.getTransactionCount(
        eRC20TokenHelper.address
      );
      const ntNonce = await ethers.provider.getTransactionCount(
        nTTokenHelper.address
      );

      const anticipatedWrappedTokenAddress = ethers.utils.getContractAddress({
        from: eRC20WrapperHelper.address,
        nonce: whNonce,
      });
      const anticipatedMemberTokenAddress = ethers.utils.getContractAddress({
        from: nTTokenHelper.address,
        nonce: ntNonce,
      });
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce: dtvsNonce,
      });

      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [erc20Token.address, tokenName, tokenSymbol],
        [ethers.constants.AddressZero, 'Members', 'MEM'],
        Object.values(defaultMintSettings),
      ]);

      const {
        plugin,
        preparedSetupData: {helpers, permissions},
      } = await dualTokenVotingSetup.callStatic.prepareInstallation(
        targetDao.address,
        data
      );

      // Expect Plugin
      expect(plugin).to.be.equal(anticipatedPluginAddress);
      expect(helpers.length).to.be.equal(2);
      expect(helpers).to.be.deep.equal([anticipatedWrappedTokenAddress, anticipatedMemberTokenAddress]);
      expect(permissions.length).to.be.equal(4);
      expect(permissions).to.deep.equal([
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPDATE_VOTING_SETTINGS_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPGRADE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          targetDao.address,
          plugin,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          anticipatedMemberTokenAddress,
          targetDao.address,
          AddressZero,
          NTT_MINT_PERMISSION_ID,
        ],
      ]);
    });

    it('correctly sets up `GovernanceWrappedERC20` helper, when an ERC20 token address is supplied and membership token is not supplied', async () => {
      const whNonce = await ethers.provider.getTransactionCount(
        eRC20WrapperHelper.address
      )
    
      const anticipatedWrappedTokenAddress = ethers.utils.getContractAddress({
        from: eRC20WrapperHelper.address,
        nonce: whNonce,
      });

      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [erc20Token.address, tokenName, tokenSymbol],
        [ethers.constants.AddressZero, 'Members', 'MEM'],
        Object.values(defaultMintSettings),
      ]);

      await dualTokenVotingSetup.prepareInstallation(targetDao.address, data);

      const GovernanceWrappedERC20Factory = await ethers.getContractFactory(
        'GovernanceWrappedERC20'
      );
      const governanceWrappedERC20Contract =
        GovernanceWrappedERC20Factory.attach(anticipatedWrappedTokenAddress);

      expect(await governanceWrappedERC20Contract.name()).to.be.equal(
        tokenName
      );
      expect(await governanceWrappedERC20Contract.symbol()).to.be.equal(
        tokenSymbol
      );

      expect(await governanceWrappedERC20Contract.underlying()).to.be.equal(
        erc20Token.address
      );
    });

    it('correctly returns plugin, helpers and permissions, when a governance token address is supplied and membership token is not supplied', async () => {
      const GovernanceERC20 = await ethers.getContractFactory(
        'GovernanceERC20'
      );
      const governanceERC20 = await GovernanceERC20.deploy(
        targetDao.address,
        'name',
        'symbol',
        {receivers: [], amounts: []}
      );

      const dtvsNonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );
      const ntNonce = await ethers.provider.getTransactionCount(
        nTTokenHelper.address
      );

      const anticipatedMemberTokenAddress = ethers.utils.getContractAddress({
        from: nTTokenHelper.address,
        nonce: ntNonce,
      });
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce: dtvsNonce,
      });

      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [governanceERC20.address, '', ''],
        [ethers.constants.AddressZero, 'Members', 'MEM'],
        Object.values(defaultMintSettings),
      ]);

      const {
        plugin,
        preparedSetupData: {helpers, permissions},
      } = await dualTokenVotingSetup.callStatic.prepareInstallation(
        targetDao.address,
        data
      );

      expect(plugin).to.be.equal(anticipatedPluginAddress);
      expect(helpers.length).to.be.equal(2);
      expect(helpers).to.be.deep.equal([governanceERC20.address, anticipatedMemberTokenAddress]);
      expect(permissions.length).to.be.equal(4);
      expect(permissions).to.deep.equal([
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPDATE_VOTING_SETTINGS_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPGRADE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          targetDao.address,
          plugin,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          anticipatedMemberTokenAddress,
          targetDao.address,
          AddressZero,
          NTT_MINT_PERMISSION_ID,
        ],
      ]);
    });

    it('correctly returns plugin, helpers and permissions, when a token address is not supplied and membership token is not supplied', async () => {
      const dtvsNonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );
      const thNonce = await ethers.provider.getTransactionCount(
        eRC20TokenHelper.address
      );
      const ntNonce = await ethers.provider.getTransactionCount(
        nTTokenHelper.address
      );

      const anticipatedPowerTokenAddress = ethers.utils.getContractAddress({
        from: eRC20TokenHelper.address,
        nonce: thNonce,
      });
      const anticipatedMemberTokenAddress = ethers.utils.getContractAddress({
        from: nTTokenHelper.address,
        nonce: ntNonce,
      });
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce: dtvsNonce,
      });
      

      const {
        plugin,
        preparedSetupData: {helpers, permissions},
      } = await dualTokenVotingSetup.callStatic.prepareInstallation(
        targetDao.address,
        defaultData
      );

      expect(plugin).to.be.equal(anticipatedPluginAddress);
      expect(helpers.length).to.be.equal(2);
      expect(helpers).to.be.deep.equal([anticipatedPowerTokenAddress, anticipatedMemberTokenAddress]);
      expect(permissions.length).to.be.equal(5);
      expect(permissions).to.deep.equal([
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPDATE_VOTING_SETTINGS_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          plugin,
          targetDao.address,
          AddressZero,
          UPGRADE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          targetDao.address,
          plugin,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          anticipatedPowerTokenAddress,
          targetDao.address,
          AddressZero,
          MINT_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          anticipatedMemberTokenAddress,
          targetDao.address,
          AddressZero,
          NTT_MINT_PERMISSION_ID,
        ],
      ]);
    });

    it('correctly sets up the plugin and helpers, when a token address is not passed and membership token is not supplied', async () => {
      const daoAddress = targetDao.address;

      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [AddressZero, tokenName, tokenSymbol],
        [AddressZero, "Member", "MEM"],
        [merkleMintToAddressArray, merkleMintToAmountArray],
      ]);

      const dtvsNonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );
      const thNonce = await ethers.provider.getTransactionCount(
        eRC20TokenHelper.address
      );
      const ntNonce = await ethers.provider.getTransactionCount(
        nTTokenHelper.address
      );

      const anticipatedPowerTokenAddress = ethers.utils.getContractAddress({
        from: eRC20TokenHelper.address,
        nonce: thNonce,
      });
      const anticipatedMemberTokenAddress = ethers.utils.getContractAddress({
        from: nTTokenHelper.address,
        nonce: ntNonce,
      });
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce: dtvsNonce,
      });

      await dualTokenVotingSetup.prepareInstallation(daoAddress, data);

      // check plugin
      const PluginFactory = await ethers.getContractFactory('DualTokenVoting');
      const dualTokenVoting = PluginFactory.attach(anticipatedPluginAddress);

      expect(await dualTokenVoting.dao()).to.be.equal(daoAddress);

      expect(await dualTokenVoting.minParticipation()).to.be.equal(
        defaultVotingSettings.minParticipation
      );
      expect(await dualTokenVoting.supportThreshold()).to.be.equal(
        defaultVotingSettings.supportThreshold
      );
      expect(await dualTokenVoting.minDuration()).to.be.equal(
        defaultVotingSettings.minDuration
      );
      expect(await dualTokenVoting.minProposerVotingPower()).to.be.equal(
        defaultVotingSettings.minProposerVotingPower
      );
      expect(await dualTokenVoting.getVotingPowerToken()).to.be.equal(
        anticipatedPowerTokenAddress
      );
      expect(await dualTokenVoting.getMembershipToken()).to.be.equal(
        anticipatedMemberTokenAddress
      );

      // check helpers
      const GovernanceTokenFactory = await ethers.getContractFactory(
        'GovernanceERC20'
      );
      const governanceTokenContract = GovernanceTokenFactory.attach(
        anticipatedPowerTokenAddress
      );

      expect(await governanceTokenContract.dao()).to.be.equal(daoAddress);
      expect(await governanceTokenContract.name()).to.be.equal(tokenName);
      expect(await governanceTokenContract.symbol()).to.be.equal(tokenSymbol);
    });

    it('correctly sets up the plugin and helpers, when a token address is not passed and membership token is supplied', async () => {
      const daoAddress = targetDao.address;

      const data = abiCoder.encode(prepareInstallationDataTypes, [
        Object.values(defaultVotingSettings),
        [AddressZero, tokenName, tokenSymbol],
        [erc721Token.address, '', ''],
        [merkleMintToAddressArray, merkleMintToAmountArray],
      ]);

      const dtvsNonce = await ethers.provider.getTransactionCount(
        dualTokenVotingSetup.address
      );
      const thNonce = await ethers.provider.getTransactionCount(
        eRC20TokenHelper.address
      );

      const anticipatedPowerTokenAddress = ethers.utils.getContractAddress({
        from: eRC20TokenHelper.address,
        nonce: thNonce,
      });
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: dualTokenVotingSetup.address,
        nonce: dtvsNonce,
      });

      await dualTokenVotingSetup.prepareInstallation(daoAddress, data);

      // check plugin
      const PluginFactory = await ethers.getContractFactory('DualTokenVoting');
      const dualTokenVoting = PluginFactory.attach(anticipatedPluginAddress);

      expect(await dualTokenVoting.dao()).to.be.equal(daoAddress);

      expect(await dualTokenVoting.minParticipation()).to.be.equal(
        defaultVotingSettings.minParticipation
      );
      expect(await dualTokenVoting.supportThreshold()).to.be.equal(
        defaultVotingSettings.supportThreshold
      );
      expect(await dualTokenVoting.minDuration()).to.be.equal(
        defaultVotingSettings.minDuration
      );
      expect(await dualTokenVoting.minProposerVotingPower()).to.be.equal(
        defaultVotingSettings.minProposerVotingPower
      );
      expect(await dualTokenVoting.getVotingPowerToken()).to.be.equal(
        anticipatedPowerTokenAddress
      );
      expect(await dualTokenVoting.getMembershipToken()).to.be.equal(
        erc721Token.address
      );

      // check helpers
      const GovernanceTokenFactory = await ethers.getContractFactory(
        'GovernanceERC20'
      );
      const governanceTokenContract = GovernanceTokenFactory.attach(
        anticipatedPowerTokenAddress
      );

      expect(await governanceTokenContract.dao()).to.be.equal(daoAddress);
      expect(await governanceTokenContract.name()).to.be.equal(tokenName);
      expect(await governanceTokenContract.symbol()).to.be.equal(tokenSymbol);
    });
  });

  describe('prepareUninstallation', async () => {
    it('fails when the wrong number of helpers is supplied', async () => {
      const plugin = ethers.Wallet.createRandom().address;

      await expect(
        dualTokenVotingSetup.prepareUninstallation(targetDao.address, {
          plugin,
          currentHelpers: [],
          data: EMPTY_DATA,
        })
      )
        .to.be.revertedWithCustomError(
          dualTokenVotingSetup,
          'WrongHelpersArrayLength'
        )
        .withArgs(0);

      await expect(
        dualTokenVotingSetup.prepareUninstallation(targetDao.address, {
          plugin,
          currentHelpers: [AddressZero, AddressZero, AddressZero],
          data: EMPTY_DATA,
        })
      )
        .to.be.revertedWithCustomError(
          dualTokenVotingSetup,
          'WrongHelpersArrayLength'
        )
        .withArgs(3);
    });

    it('correctly returns permissions, when the required number of helpers is supplied', async () => {
      const plugin = ethers.Wallet.createRandom().address;
      const GovernanceERC20 = await ethers.getContractFactory(
        'GovernanceERC20'
      );
      const GovernanceWrappedERC20 = await ethers.getContractFactory(
        'GovernanceWrappedERC20'
      );
      const governanceERC20 = await GovernanceERC20.deploy(
        targetDao.address,
        tokenName,
        tokenSymbol,
        {receivers: [], amounts: []}
      );

      const governanceWrappedERC20 = await GovernanceWrappedERC20.deploy(
        governanceERC20.address,
        tokenName,
        tokenSymbol
      );

      const NTToken = await ethers.getContractFactory(
        'NTToken'
      ) as NTToken__factory;
      const ERC721Mock = await ethers.getContractFactory(
        'ERC721Mock'
      ) as ERC721Mock__factory;

      const nTToken = await NTToken.deploy(
        targetDao.address,
        "Members",
        "MEM"
      );

      const eRC721Mock = await ERC721Mock.deploy();
      // When the helpers contain governanceWrappedERC20 token
      const permissions1 =
        await dualTokenVotingSetup.callStatic.prepareUninstallation(
          targetDao.address,
          {
            plugin,
            currentHelpers: [governanceWrappedERC20.address, eRC721Mock.address],
            data: EMPTY_DATA,
          }
        );

      const essentialPermissions = [
        [
          Operation.Revoke,
          plugin,
          targetDao.address,
          AddressZero,
          UPDATE_VOTING_SETTINGS_PERMISSION_ID,
        ],
        [
          Operation.Revoke,
          plugin,
          targetDao.address,
          AddressZero,
          UPGRADE_PERMISSION_ID,
        ],
        [
          Operation.Revoke,
          targetDao.address,
          plugin,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
      ];
      

      expect(permissions1.length).to.be.equal(3);
      expect(permissions1).to.deep.equal([...essentialPermissions]);

      const permissions2 =
        await dualTokenVotingSetup.callStatic.prepareUninstallation(
          targetDao.address,
          {
            plugin,
            currentHelpers: [governanceERC20.address, eRC721Mock.address],
            data: EMPTY_DATA,
          }
        );

      expect(permissions2.length).to.be.equal(4);
      expect(permissions2).to.deep.equal([
        ...essentialPermissions,
        [
          Operation.Revoke,
          governanceERC20.address,
          targetDao.address,
          AddressZero,
          MINT_PERMISSION_ID,
        ],
      ]);

      const permissions3 =
        await dualTokenVotingSetup.callStatic.prepareUninstallation(
          targetDao.address,
          {
            plugin,
            currentHelpers: [governanceERC20.address, nTToken.address],
            data: EMPTY_DATA,
          }
        );
      expect(permissions3.length).to.be.equal(5);
      expect(permissions3).to.deep.equal([
        ...essentialPermissions,
        [
          Operation.Revoke,
          governanceERC20.address,
          targetDao.address,
          AddressZero,
          MINT_PERMISSION_ID,
        ],
        [
          Operation.Revoke,
          nTToken.address,
          targetDao.address,
          AddressZero,
          NTT_MINT_PERMISSION_ID,
        ],
      ]);

      const permissions4 =
        await dualTokenVotingSetup.callStatic.prepareUninstallation(
          targetDao.address,
          {
            plugin,
            currentHelpers: [governanceWrappedERC20.address, nTToken.address],
            data: EMPTY_DATA,
          }
        );

      expect(permissions4.length).to.be.equal(4);
      expect(permissions4).to.deep.equal([
        ...essentialPermissions,
        [
          Operation.Revoke,
          nTToken.address,
          targetDao.address,
          AddressZero,
          NTT_MINT_PERMISSION_ID,
        ],
      ]);
    });
  });
});
