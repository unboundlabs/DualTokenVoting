import {
  DAO,
  PluginSetupProcessor,
  PluginSetupProcessor__factory,
} from '../../typechain';
import {osxContracts, networkNameMapping} from '../../utils/helpers';
import {Operation} from './types';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';

export async function createPluginSetupProcessor(
  signer: SignerWithAddress,
  dao: DAO
): Promise<PluginSetupProcessor> {
  // Create the PluginSetupProcessor

  const hardhatForkNetwork = process.env.HARDHAT_FORK_NETWORK
    ? process.env.HARDHAT_FORK_NETWORK
    : 'mainnet';

  const psp = new PluginSetupProcessor__factory(signer).attach(
    osxContracts[networkNameMapping[hardhatForkNetwork]].PluginSetupProcessor
  );

  // grant the owner full permission for plugins
  await dao.applySingleTargetPermissions(psp.address, [
    {
      operation: Operation.Grant,
      who: signer.address,
      permissionId: await psp.APPLY_INSTALLATION_PERMISSION_ID(),
    },
    {
      operation: Operation.Grant,
      who: signer.address,
      permissionId: await psp.APPLY_UPDATE_PERMISSION_ID(),
    },
    {
      operation: Operation.Grant,
      who: signer.address,
      permissionId: await psp.APPLY_UNINSTALLATION_PERMISSION_ID(),
    },
  ]);
  // grant the PSP root to apply stuff
  await dao.grant(dao.address, psp.address, await dao.ROOT_PERMISSION_ID());

  return psp;
}
