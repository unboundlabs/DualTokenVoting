// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {TokenChecker} from "./TokenChecker.sol";

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {NTToken} from "./NTToken.sol";



/// @title NTTokenHelper
/// @author Unbound Labs, Ketul "Jay" Patel -- 2023
/// @notice The helper contract to create or use a non-transferable token to be used for membership
contract NTTokenHelper {
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

    /// @notice Thrown if supplied member token address is not currently supported.
    error MemberTokenNotSupported(address token);

    constructor() {}

    /// @notice Verifies or deploys a new NT token
    /// @param dao_ the associated dao
    /// @param tok_ the token address or zero address if creating a new token
    /// @param name_ the name of the new token to be created (only applicable if zero address is given for the token)
    /// @param symbol_ the symbol of the new token to be created (only applicable if zero address is given)
    function verifyOrDeployToken(IDAO dao_, address tok_, string memory name_, string memory symbol_) public returns (CreatedToken memory) {
        CreatedToken memory returnToken = CreatedToken(
            tok_,
            false
        );
        if (tok_ != address(0)) {

            // Check if the member token is supported for use.
            // For a member token to be used it must have a balanceOf(address) function
            // Membership, voting & proposal creation privileges are determined by balanceOf > 0

            if (!tok_.isContract()) {
                revert TokenNotContract(tok_);
            }

            // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20, [3] = IERC721Upgradeable, [4] = IERC721
            bool[] memory supportedIds = tok_.getTokenInterfaceIds();

            // This is an overly restrictive method 
            // Instead of restricting to ERC721 or ERC721Upgradeable one possibility could be to
            // check for support of the balanceOf(address) method via Interface or staticcall
            if(!supportedIds[3] || !supportedIds[4]) {
                revert MemberTokenNotSupported(tok_);
            }
            
            // TODO: Add support for ERC1155 / ERC1155Upgradeable
        } else {
            // Create new member token
            returnToken.addr = address(
                new NTToken(
                    IDAO(dao_),
                    name_,
                    symbol_
                )
            );
            // Since we're creating a new token specifically for the DAO flag that permissions are required
            returnToken.permissionsRequired = true;
        }
        return returnToken;
    }
    
}