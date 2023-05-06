import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {ethers} from 'hardhat';
import {expect} from 'chai';

import {
    NTToken,
    NTToken__factory
} from '../../typechain'
import { Address } from 'hardhat-deploy/types';

let signers: SignerWithAddress[];
let token: NTToken;
let TokenFactory: NTToken__factory

describe.only("Non-Transferable Token", async () => {
    before(async () => {
        signers = await ethers.getSigners();
    })
    describe("Token Deployment", async () => {
        it("Successfully deploy the token contract", async () => {
            TokenFactory = await ethers.getContractFactory(
                'NTToken',
                signers[0]
            ) as NTToken__factory;
    
            token = await TokenFactory.deploy(
                "Non-Transferable Token Name",
                "NTT",
            );
            expect(await token.name()).to.be.equal("Non-Transferable Token Name")
            expect(await token.symbol()).to.be.equal("NTT")
        });
    })
    describe("Token Minting", async () => {
        before(async () => {
            await token.safeMint(signers[1].address) // TokenId: 0
            await token.safeMint(signers[2].address) // TokenId: 1
            await token.safeMint(signers[3].address) // TokenId: 2
            await token.safeMint(signers[4].address) // TokenId: 3
        })
        it("successfully mints tokens", async () => {
            expect(await token.balanceOf(signers[1].address)).to.be.equal(1)
            expect(await token.balanceOf(signers[2].address)).to.be.equal(1)
            expect(await token.balanceOf(signers[3].address)).to.be.equal(1)
            expect(await token.balanceOf(signers[4].address)).to.be.equal(1)
        })
        it("successfully burns tokens", async () => {
            await token.connect(signers[4]).burn(3)
            expect(await token.balanceOf(signers[4].address)).to.be.equal(0)
        })
        it("denies minting additional tokens for an account", async () => {
            await expect(token.safeMint(signers[1].address)).to.be.revertedWith("Recipient cannot own multiple tokens.")
            await expect(token.safeMint(signers[2].address)).to.be.revertedWith("Recipient cannot own multiple tokens.")
            await expect(token.safeMint(signers[3].address)).to.be.revertedWith("Recipient cannot own multiple tokens.")
        })
        it("denies transferring of tokens", async () => {
            await expect(token.connect(signers[2]).transferFrom(signers[2].address, signers[5].address, 1)).to.be.revertedWith("This a Soulbound token. It cannot be transferred. It can only be burned by the token owner.")
        })
        it("successfully returns the supply", async () => {
            expect(await token.totalSupply()).to.be.equal(3)
        })
        it("successfully returns all owner addresses not including burn address", async () => {
            let owners = await token.allOwners();
            expect(owners).to.be.an('array').that.does.not.include(signers[4].address)
            expect(owners).to.be.an('array').that.does.not.include(ethers.constants.AddressZero)
            expect(owners).to.be.an('array').that.includes(signers[1].address)
            expect(owners).to.be.an('array').that.includes(signers[2].address)
            expect(owners).to.be.an('array').that.includes(signers[3].address)
        })
    });

});