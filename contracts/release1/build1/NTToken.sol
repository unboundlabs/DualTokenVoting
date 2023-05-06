// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// A simple implementation of a Soulbound Token called NTToken (NT for Non-Transferable)
// Uses ERC721 as a base
// Modifies beforeTokenTransfer to prevent transfers and require recipient balance to be 0
// TODO: Switch to Upgradable inheritance
// TODO: Implement DaoAuthorizableUpgradeable for permissions
// TODO: Abstract out interface and use an Interface design pattern to make this more extensible with totalSupply & allOwners
// TODO: Expand inheritance so this isn't limited to ERC721, NTT should restrict transfer, and optionally implement totalSupply & allOwners

contract NTToken is ERC721, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint256 private _supply;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function safeMint(address to) public onlyOwner {
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

    function _burn(uint256 tokenId) internal override(ERC721) {
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