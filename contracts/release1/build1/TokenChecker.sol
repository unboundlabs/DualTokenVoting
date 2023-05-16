// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IGovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/IGovernanceWrappedERC20.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {NTToken} from "./NTToken.sol";
import {MajorityVotingBase} from "@aragon/osx/plugins/governance/majority-voting/MajorityVotingBase.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";


// Library of token checking methods

library TokenChecker {
    using Address for address;
    using ERC165Checker for address;

    /// @notice Retrieves the interface identifiers supported by the token contract.
    /// @dev It is crucial to verify if the provided token address represents a valid contract before using the below.
    /// @param token The token address
    function getTokenInterfaceIds(address token) public view returns (bool[] memory) {
        bytes4[] memory interfaceIds = new bytes4[](5);
        interfaceIds[0] = type(IERC20Upgradeable).interfaceId;
        interfaceIds[1] = type(IVotesUpgradeable).interfaceId;
        interfaceIds[2] = type(IGovernanceWrappedERC20).interfaceId;
        interfaceIds[3] = type(IERC721Upgradeable).interfaceId;
        interfaceIds[4] = type(IERC721).interfaceId;
        return token.getSupportedInterfaces(interfaceIds);
    }

    function isERC20(address token) public view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Upgradeable.balanceOf.selector, address(this))
        );
        return success && data.length == 0x20;
    }

    function isGovernanceERC20(address tok) public view returns (bool) {
        bool[] memory supportedIds = getTokenInterfaceIds(tok);
        return (supportedIds[0] && supportedIds[1] && !supportedIds[2]);
    }

    function isNTT(address tok) public view returns (bool) {
        bytes4 ntt_interface =
            NTToken.initialize.selector ^ 
            NTToken.safeMint.selector ^ 
            NTToken.burn.selector ^
            NTToken.totalSupply.selector ^
            NTToken.allOwners.selector;

        return tok.supportsInterface(ntt_interface);
    }
    
}