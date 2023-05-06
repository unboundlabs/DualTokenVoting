// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IGovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/IGovernanceWrappedERC20.sol";
import {MajorityVotingBase} from "@aragon/osx/plugins/governance/majority-voting/MajorityVotingBase.sol";
import {DualTokenVoting} from "./DualTokenVoting.sol";
import {NTToken} from "./NTToken.sol";

/// @title DualTokenVotingSetup
/// @author Aragon Association - 2022-2023
/// @notice The setup contract of the `DualTokenVoting` plugin.
contract DualTokenVotingSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /// @notice The address of the `DualTokenVoting` base contract.
    DualTokenVoting private immutable dualTokenVotingBase;

    /// @notice The address of the `GovernanceERC20` base contract.
    address public immutable governanceERC20Base;

    /// @notice The address of the `GovernanceWrappedERC20` base contract.
    address public immutable governanceWrappedERC20Base;

    /// @notice The token settings struct.
    /// @param addr The token address. If this is `address(0)`, a new `GovernanceERC20` token is deployed. If not, the existing token is wrapped as an `GovernanceWrappedERC20`.
    /// @param name The token name. This parameter is only relevant if the token address is `address(0)`.
    /// @param name The token symbol. This parameter is only relevant if the token address is `address(0)`.
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice Thrown if feature is not supported in current version.
    error FeatureNotSupportedInCurrentRelease();

    /// @notice The contract constructor, that deploys the bases.
    constructor() {
        governanceERC20Base = address(
            new GovernanceERC20(
                IDAO(address(0)),
                "",
                "",
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
            )
        );
        governanceWrappedERC20Base = address(
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
        );
        dualTokenVotingBase = new DualTokenVoting();
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

        address powerToken = powerTokenSettings.addr;
        address memberToken = memberTokenSettings.addr;

        // Prepare helpers.
        address[] memory helpers = new address[](1);

        if (powerToken != address(0)) {
            if (!powerToken.isContract()) {
                revert TokenNotContract(powerToken);
            }

            if (!_isERC20(powerToken)) {
                revert TokenNotERC20(powerToken);
            }

            // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20
            bool[] memory supportedIds = _getTokenInterfaceIds(powerToken);

            if (
                // If token supports none of them
                // it's simply ERC20 which gets checked by _isERC20
                // Currently, not a satisfiable check.
                (!supportedIds[0] && !supportedIds[1] && !supportedIds[2]) ||
                // If token supports IERC20, but neither
                // IVotes nor IGovernanceWrappedERC20, it needs wrapping.
                (supportedIds[0] && !supportedIds[1] && !supportedIds[2])
            ) {
                powerToken = governanceWrappedERC20Base.clone();
                // User already has a token. We need to wrap it in
                // GovernanceWrappedERC20 in order to make the token
                // include governance functionality.
                GovernanceWrappedERC20(powerToken).initialize(
                    IERC20Upgradeable(powerTokenSettings.addr),
                    powerTokenSettings.name,
                    powerTokenSettings.symbol
                );
            }
        } else {
            // Clone a `GovernanceERC20`.
            powerToken = governanceERC20Base.clone();
            GovernanceERC20(powerToken).initialize(
                IDAO(_dao),
                powerTokenSettings.name,
                powerTokenSettings.symbol,
                mintSettings
            );
        }

        if (memberToken != address(0)) {
            // TODO: Handle this case where a user already has a token they'd like to use
            // This will likely require some edits to the NTToken design
            // For proof of concept rely on installation creating a new memberToken
            revert FeatureNotSupportedInCurrentRelease();
        } else {
            // Create new member token
            NTToken newMemberToken = new NTToken(
                memberTokenSettings.name,
                memberTokenSettings.symbol
            );
            memberToken = address(newMemberToken);
        }

        //TODO: adjust this helpers to add memberToken and figure out why it's needed for uninstall
        helpers[0] = powerToken;

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(dualTokenVotingBase),
            abi.encodeWithSelector(DualTokenVoting.initialize.selector, _dao, votingSettings, powerToken, memberToken)
        );

        //TODO: Figure out what needs to be adjusted here for permissions...

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](
                powerTokenSettings.addr != address(0) ? 3 : 4
            );

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

        if (powerTokenSettings.addr == address(0)) {
            bytes32 tokenMintPermission = GovernanceERC20(powerToken).MINT_PERMISSION_ID();

            permissions[3] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Grant,
                powerToken,
                _dao,
                PermissionLib.NO_CONDITION,
                tokenMintPermission
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
        if (helperLength != 1) {
            revert WrongHelpersArrayLength({length: helperLength});
        }

        // token can be either GovernanceERC20, GovernanceWrappedERC20, or IVotesUpgradeable, which
        // does not follow the GovernanceERC20 and GovernanceWrappedERC20 standard.
        address token = _payload.currentHelpers[0];

        bool[] memory supportedIds = _getTokenInterfaceIds(token);

        bool isGovernanceERC20 = supportedIds[0] && supportedIds[1] && !supportedIds[2];

        permissions = new PermissionLib.MultiTargetPermission[](isGovernanceERC20 ? 4 : 3);

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
                token,
                _dao,
                PermissionLib.NO_CONDITION,
                GovernanceERC20(token).MINT_PERMISSION_ID()
            );
        }
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(dualTokenVotingBase);
    }

    /// @notice Retrieves the interface identifiers supported by the token contract.
    /// @dev It is crucial to verify if the provided token address represents a valid contract before using the below.
    /// @param token The token address
    function _getTokenInterfaceIds(address token) private view returns (bool[] memory) {
        bytes4[] memory interfaceIds = new bytes4[](3);
        interfaceIds[0] = type(IERC20Upgradeable).interfaceId;
        interfaceIds[1] = type(IVotesUpgradeable).interfaceId;
        interfaceIds[2] = type(IGovernanceWrappedERC20).interfaceId;
        return token.getSupportedInterfaces(interfaceIds);
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _isERC20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Upgradeable.balanceOf.selector, address(this))
        );
        return success && data.length == 0x20;
    }
}
