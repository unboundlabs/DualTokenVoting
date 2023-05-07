// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

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

    /// @notice The address of the `NTToken` base contract.
    address public immutable nTToken;

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

    /// @notice Thrown if supplied member token address is not currently supported.
    error MemberTokenNotSupported(address token);

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
        nTToken = address(
            new NTToken(
                IDAO(address(0)),
                "",
                ""
            )
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
        address[] memory tokens = new address[](2);
        tokens[0] = powerTokenSettings.addr;
        tokens[1] = memberTokenSettings.addr;

        // Prepare helpers.
        address[] memory helpers = new address[](2);

        if (tokens[0] != address(0)) {
            if (!tokens[0].isContract()) {
                revert TokenNotContract(tokens[0]);
            }

            if (!_isERC20(tokens[0])) {
                revert TokenNotERC20(tokens[0]);
            }

            // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20
            bool[] memory supportedIds = _getTokenInterfaceIds(tokens[0]);

            if (
                // If token supports none of them
                // it's simply ERC20 which gets checked by _isERC20
                // Currently, not a satisfiable check.
                (!supportedIds[0] && !supportedIds[1] && !supportedIds[2]) ||
                // If token supports IERC20, but neither
                // IVotes nor IGovernanceWrappedERC20, it needs wrapping.
                (supportedIds[0] && !supportedIds[1] && !supportedIds[2])
            ) {
                tokens[0] = governanceWrappedERC20Base.clone();
                // User already has a token. We need to wrap it in
                // GovernanceWrappedERC20 in order to make the token
                // include governance functionality.
                GovernanceWrappedERC20(tokens[0]).initialize(
                    IERC20Upgradeable(powerTokenSettings.addr),
                    powerTokenSettings.name,
                    powerTokenSettings.symbol
                );
            }
        } else {
            // Clone a `GovernanceERC20`.
            tokens[0] = governanceERC20Base.clone();
            GovernanceERC20(tokens[0]).initialize(
                IDAO(_dao),
                powerTokenSettings.name,
                powerTokenSettings.symbol,
                mintSettings
            );
        }

        if (tokens[1] != address(0)) {

            // Check if the member token is supported for use.
            // For a member token to be used it must have a balanceOf(address) function
            // Membership, voting & proposal creation privileges are determined by balanceOf > 0

            if (!tokens[1].isContract()) {
                revert TokenNotContract(tokens[1]);
            }

            // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20, [3] = IERC721Upgradeable, [4] = IERC721
            bool[] memory supportedIds = _getTokenInterfaceIds(tokens[1]);

            // This is an overly restrictive method 
            // Instead of restricting to ERC721 or ERC721Upgradeable one possibility could be to
            // check for support of the balanceOf(address) method via Interface or staticcall
            if(!supportedIds[3] || !supportedIds[4]) {
                revert MemberTokenNotSupported(tokens[1]);
            }
            // TODO: Add support for ERC1155 / ERC1155Upgradeable
        } else {
            // Create new member token
            tokens[1] = nTToken.clone();
            NTToken(tokens[1]).initialize(
                IDAO(_dao),
                memberTokenSettings.name,
                memberTokenSettings.symbol
            );
        }

        //TODO: adjust this helpers to add memberToken and figure out why it's needed for uninstall
        helpers[0] = tokens[0];
        helpers[1] = tokens[1];

        // Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(dualTokenVotingBase),
            abi.encodeWithSelector(DualTokenVoting.initialize.selector, _dao, votingSettings, tokens[0], tokens[1])
        );

        //TODO: Figure out what needs to be adjusted here for permissions...

        // Prepare permissions
        uint256 numPermissions = 3;
        if(powerTokenSettings.addr == address(0)) {
            numPermissions++;
        }
        if(memberTokenSettings.addr == address(0)) {
            numPermissions++;
        }

        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](numPermissions);

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
            bytes32 tokenMintPermission = GovernanceERC20(tokens[0]).MINT_PERMISSION_ID();

            permissions[3] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Grant,
                tokens[0],
                _dao,
                PermissionLib.NO_CONDITION,
                tokenMintPermission
            );
        }
        if (memberTokenSettings.addr == address(0)) {
            bytes32 memberTokenMintPermission = NTToken(tokens[1]).NTT_MINT_PERMISSION_ID();

            permissions[numPermissions-1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Grant,
                tokens[1],
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

        bool[] memory supportedIds = _getTokenInterfaceIds(tokens[0]);

        bool isGovernanceERC20 = supportedIds[0] && supportedIds[1] && !supportedIds[2];
        bool isNTT = _isNTT(tokens[1]);

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
                GovernanceERC20(tokens[0]).MINT_PERMISSION_ID()
            );
        }
        if (isNTT) {
            permissions[permissions.length-1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.Revoke,
                tokens[1],
                _dao,
                PermissionLib.NO_CONDITION,
                NTToken(tokens[1]).NTT_MINT_PERMISSION_ID()
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
        bytes4[] memory interfaceIds = new bytes4[](5);
        interfaceIds[0] = type(IERC20Upgradeable).interfaceId;
        interfaceIds[1] = type(IVotesUpgradeable).interfaceId;
        interfaceIds[2] = type(IGovernanceWrappedERC20).interfaceId;
        interfaceIds[3] = type(IERC721Upgradeable).interfaceId;
        interfaceIds[4] = type(IERC721).interfaceId;
        return token.getSupportedInterfaces(interfaceIds);
    }
    
    function _isNTT(address token) private view returns (bool) {
        bytes4 ntt_interface =
            NTToken.initialize.selector ^ 
            NTToken.safeMint.selector ^ 
            NTToken.burn.selector ^
            NTToken.totalSupply.selector ^
            NTToken.allOwners.selector;

        return token.supportsInterface(ntt_interface);
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
