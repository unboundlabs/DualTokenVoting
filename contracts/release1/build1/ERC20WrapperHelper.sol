// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";


import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

/// @title ERC20WrapperHelper
/// @author Unbound Labs, Ketul "Jay" Patel -- 2023
/// @notice The helper contract to wrap an ERC20 governance token to be used in ERC20TokenHelper
contract ERC20WrapperHelper {
    using Address for address;

    constructor() {}

    /// @notice Wraps a given ERC20 token for governance
    /// @param token_ the token address to be wrapped
    /// @param name_ the name of the token to be wrapped
    /// @param symbol_ the symbol of the token to be wrapped
    function wrapERC20(IERC20Upgradeable token_, string calldata name_, string calldata symbol_) public returns (address) {
    
        return address(new GovernanceWrappedERC20(
            IERC20Upgradeable(token_),
            name_,
            symbol_
        ));
    }
    
}