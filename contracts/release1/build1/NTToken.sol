// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

// A simple implementation of a Soulbound Token called NTToken (NT for Non-Transferable)
// Uses ERC721 as a base
// Modifies beforeTokenTransfer to prevent transfers and require recipient balance to be 0
// TODO: Implement DaoAuthorizableUpgradeable for permissions
// TODO: Abstract out interface and use an Interface design pattern to make this more extensible with totalSupply & allOwners
// TODO: Expand inheritance so this isn't limited to ERC721, NTT should restrict transfer, and optionally implement totalSupply & allOwners

contract NTToken is Initializable, ERC721Upgradeable, DaoAuthorizableUpgradeable   {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant NTT_INTERFACE_ID =
        this.initialize.selector ^ 
        this.safeMint.selector ^ 
        this.burn.selector ^
        this.totalSupply.selector ^
        this.allOwners.selector;

    bytes32 public constant NTT_MINT_PERMISSION_ID = keccak256("NTT_MINT_PERMISSION");


    CountersUpgradeable.Counter private _tokenIdCounter;
    uint256 private _supply;

    constructor(IDAO dao_, string memory name_, string memory symbol_) {
        initialize(dao_, name_, symbol_);
    }

    function initialize(IDAO dao_, string memory name_, string memory symbol_) initializer public {
        __ERC721_init(name_, symbol_);
        __DaoAuthorizableUpgradeable_init(dao_);
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == NTT_INTERFACE_ID ||
            _interfaceId == type(DaoAuthorizableUpgradeable).interfaceId ||
            _interfaceId == type(IERC721Upgradeable).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    function safeMint(address to) public auth(NTT_MINT_PERMISSION_ID) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Only the owner of the token can burn it.");
        _burn(tokenId);
    }

    // A burn function that burns the owner's token if it exists
    

    // The balanceOf check will not work for ERC721Consecutive batchSize minting
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) virtual override internal {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        require(from == address(0) || to == address(0), "This a Soulbound token. It cannot be transferred. It can only be burned by the token owner.");
        if(from == address(0)) {
            require(balanceOf(to) == 0, "Recipient cannot own multiple tokens.");
            _supply++;
        }
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable) {
        _supply--;
        super._burn(tokenId);
    }

    // totalSupply similar to ERC721Enumerable to aid in getting all owners via ownerOf
    function totalSupply() public view returns (uint256) {
        return _supply;
    }

    // TODO: this can be overly resource intensive, refactor appropriately
    // This will return zero address for all burned tokens
    function allOwners() public view returns (address[] memory) {
        uint256 i=0;
        address[] memory addresses = new address[](totalSupply());
        for(i=0; i<_tokenIdCounter.current(); i++) { // TODO: Find a better solution here potential here or make supply count stronger using Counters or similar
            if(_exists(i)) {
                addresses[i] = ownerOf(i);
            }  
        }
        return addresses;
    }
}