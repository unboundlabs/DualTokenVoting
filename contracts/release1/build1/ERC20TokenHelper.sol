// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {TokenChecker} from "./TokenChecker.sol";


import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {ERC20WrapperHelper} from "./ERC20WrapperHelper.sol";

/// @title ERC20TokenHelper
/// @author Unbound Labs, Ketul "Jay" Patel -- 2023
/// @notice The helper contract to create or wrap an ERC20 governance token to be used in DualTokenVoting
contract ERC20TokenHelper {
    using Address for address;
    using ERC165Checker for address;
    using TokenChecker for address;

    struct CreatedToken {
        address addr;
        bool permissionsRequired;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    ERC20WrapperHelper public immutable wrapperHelper;

    constructor(address _wrapperHelper) {
        wrapperHelper = ERC20WrapperHelper(_wrapperHelper);
    }

    /// @notice Verifies/Wraps or deploys a new GovernanceERC20 token
    /// @param dao_ the associated dao
    /// @param tok_ the token address or zero address if creating a new token
    /// @param name_ the name of the new token to be created (only applicable if zero address is given for the token)
    /// @param symbol_ the symbol of the new token to be created (only applicable if zero address is given)
    /// @param mintSettings the mint settings of the new token to be created (only applicable if zero address is given)
    function verifyOrDeployToken(IDAO dao_, address tok_, string calldata name_, string calldata symbol_, GovernanceERC20.MintSettings calldata mintSettings) public returns (CreatedToken memory returnToken) {
        if (tok_ != address(0)) {
            returnToken.addr = tok_;
            returnToken.permissionsRequired = false;
            if (!tok_.isContract()) {
                revert TokenNotContract(tok_);
            }

            if (!tok_.isERC20()) {
                revert TokenNotERC20(tok_);
            }

            // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20
            bool[] memory supportedIds = tok_.getTokenInterfaceIds();

            if (
                // If token supports none of them
                // it's simply ERC20 which gets checked by _isERC20
                // Currently, not a satisfiable check.
                (!supportedIds[0] && !supportedIds[1] && !supportedIds[2]) ||
                // If token supports IERC20, but neither
                // IVotes nor IGovernanceWrappedERC20, it needs wrapping.
                (supportedIds[0] && !supportedIds[1] && !supportedIds[2])
            ) {
                returnToken.addr = wrapperHelper.wrapERC20(
                    IERC20Upgradeable(tok_),
                    name_,
                    symbol_
                );
                returnToken.permissionsRequired = false;
            }
        } else {
            // Clone a `GovernanceERC20`.
            returnToken.addr = address(new GovernanceERC20(
                IDAO(dao_),
                name_,
                symbol_,
                mintSettings
            ));
            returnToken.permissionsRequired = true;
        }
        return returnToken;
    }
    
}