// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {TokenChecker} from "./TokenChecker.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {MajorityVotingBase} from "@aragon/osx/plugins/governance/majority-voting/MajorityVotingBase.sol";
import {DualTokenVoting} from "./DualTokenVoting.sol";
import {NTTokenHelper} from "./NTTokenHelper.sol";
import {ERC20TokenHelper} from "./ERC20TokenHelper.sol";

/// @title DualTokenVotingSetup
/// @author Unbound Labs, Ketul "Jay" Patel -- 2023
/// @notice The setup contract of the `DualTokenVoting` plugin.
/// @notice This setup contract handles permissioning for the plugin and tokens. Tokens are created/wrapped by helper contracts
contract DualTokenVotingSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using TokenChecker for address;

    /// @notice The address of the `DualTokenVoting` base contract.
    DualTokenVoting private immutable dualTokenVotingBase;

    /// @notice The address of the `NTTHelper` base contract.
    NTTokenHelper public immutable memberTokenHelper;

    /// @notice The address of the `NTTHelper` base contract.
    ERC20TokenHelper public immutable governanceTokenHelper;

    /// @notice The token settings struct.
    /// @param addr The token address. If this is `address(0)`, a new `GovernanceERC20` token is deployed. If not, the existing token is wrapped as an `GovernanceWrappedERC20`.
    /// @param name The token name. This parameter is only relevant if the token address is `address(0)`.
    /// @param name The token symbol. This parameter is only relevant if the token address is `address(0)`.
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor, that deploys the bases.
    constructor(address _governanceTokenHelper, address _memberTokenHelper) {
        
        dualTokenVotingBase = new DualTokenVoting();

        governanceTokenHelper = ERC20TokenHelper(_governanceTokenHelper);

        memberTokenHelper = NTTokenHelper(_memberTokenHelper);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `TokenVoting` plugin,
        // and the required helpers
        (
            MajorityVotingBase.VotingSettings memory votingSettings,
            TokenSettings memory powerTokenSettings,
            TokenSettings memory memberTokenSettings,
            // only used for GovernanceERC20(token is not passed)
            GovernanceERC20.MintSettings memory mintSettings
        ) = abi.decode(
                _data,
                (MajorityVotingBase.VotingSettings, TokenSettings, TokenSettings, GovernanceERC20.MintSettings)
            );
        address[] memory helpers = new address[](2);
        
        ERC20TokenHelper.CreatedToken memory verifiedGovernanceToken = governanceTokenHelper.verifyOrDeployToken(
            IDAO(_dao),
            powerTokenSettings.addr,
            powerTokenSettings.name,
            powerTokenSettings.symbol,
            mintSettings
        );

        NTTokenHelper.CreatedToken memory verifiedMemberToken = memberTokenHelper.verifyOrDeployToken(
            IDAO(_dao),
            memberTokenSettings.addr,
            memberTokenSettings.name,
            memberTokenSettings.symbol
        );
        helpers[0] = verifiedGovernanceToken.addr;
        helpers[1] = verifiedMemberToken.addr;

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(dualTokenVotingBase),
            abi.encodeWithSelector(DualTokenVoting.initialize.selector, _dao, votingSettings, helpers[0], helpers[1])
        );

        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](verifiedGovernanceToken.permissionsRequired && verifiedMemberToken.permissionsRequired ? 5 : verifiedGovernanceToken.permissionsRequired || verifiedMemberToken.permissionsRequired ? 4 : 3);

        // Set plugin permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            dualTokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            dualTokenVotingBase.UPGRADE_PLUGIN_PERMISSION_ID()
        );

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            _dao,
            plugin,
            PermissionLib.NO_CONDITION,
            DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        );

        if (verifiedMemberToken.permissionsRequired) {
            bytes32 tokenMintPermission = keccak256("MINT_PERMISSION");

            permissions[3] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Grant,
                helpers[0],
                _dao,
                PermissionLib.NO_CONDITION,
                tokenMintPermission
            );
        }
        if (verifiedMemberToken.permissionsRequired) {
            bytes32 memberTokenMintPermission = keccak256("NTT_MINT_PERMISSION");

            permissions[permissions.length-1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Grant,
                helpers[1],
                _dao,
                PermissionLib.NO_CONDITION,
                memberTokenMintPermission
            );
        }

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 2) {
            revert WrongHelpersArrayLength({length: helperLength});
        }

        // token can be either GovernanceERC20, GovernanceWrappedERC20, or IVotesUpgradeable, which
        // does not follow the GovernanceERC20 and GovernanceWrappedERC20 standard.
        address[] memory tokens = new address[](2);

        tokens[0] = _payload.currentHelpers[0];
        tokens[1] = _payload.currentHelpers[1];

        bool isGovernanceERC20 = tokens[0].isGovernanceERC20();

        bool isNTT = tokens[1].isNTT();

        permissions = new PermissionLib.MultiTargetPermission[](isGovernanceERC20 && isNTT ? 5 : isGovernanceERC20 || isNTT ? 4 : 3);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            dualTokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        );

        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            _dao,
            PermissionLib.NO_CONDITION,
            dualTokenVotingBase.UPGRADE_PLUGIN_PERMISSION_ID()
        );

        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _dao,
            _payload.plugin,
            PermissionLib.NO_CONDITION,
            DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        );

        // Revocation of permission is necessary only if the deployed token is GovernanceERC20,
        // as GovernanceWrapped does not possess this permission. Only return the following
        // if it's type of GovernanceERC20, otherwise revoking this permission wouldn't have any effect.
        if (isGovernanceERC20) {
            permissions[3] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Revoke,
                tokens[0],
                _dao,
                PermissionLib.NO_CONDITION,
                keccak256("MINT_PERMISSION")
            );
        }
        if (isNTT) {
            permissions[permissions.length-1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Revoke,
                tokens[1],
                _dao,
                PermissionLib.NO_CONDITION,
                keccak256("NTT_MINT_PERMISSION")
            );
        }
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(dualTokenVotingBase);
    }
}
