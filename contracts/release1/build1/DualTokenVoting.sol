// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE, _applyRatioCeiled} from "@aragon/osx/plugins/utils/Ratio.sol";
import {MajorityVotingBase} from "@aragon/osx/plugins/governance/majority-voting/MajorityVotingBase.sol";
import {IMajorityVoting} from "@aragon/osx/plugins/governance/majority-voting/IMajorityVoting.sol";
import {NTToken} from "./NTToken.sol";

/// @title DualTokenVoting
/// @author Unbound Labs, Ketul "Jay" Patel -- 2023
/// @notice The dual access and majority voting implementation using an [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes) compatible governance power token and a custom built ERC721 NTT (Non-Transferable Token or Soulbound Token) to determine membership/access.
/// @dev This contract inherits from `MajorityVotingBase` and implements the `IMajorityVoting` interface.
/*
    Notes:
        The primary function of the DualTokenVoting contract is to introduce a membership token that limits voting ability to owners of the membership token.
        While membership and therefore voting ability is limited to owners of the membership token,
        Voting power is still determined by the [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes) compatible governance token.
        Therefore the voting settings defined in MajorityVotingBase still apply.

    TODO: 
*/
contract DualTokenVoting is IMembership, MajorityVotingBase {
    using SafeCastUpgradeable for uint256;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant TOKEN_VOTING_INTERFACE_ID =
        this.initialize.selector ^ this.getVotingPowerToken.selector ^ this.getMembershipToken.selector;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes) compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingPowerToken;

    /// @notice A custom NTToken that represents the membership or access token;
    NTToken private membershipToken;

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

    /// @notice Thrown if no members
    error NoMembers();

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _votingSettings The voting settings.
    /// @param _powerToken The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token used for voting.
    /// @param _memberToken The ERC721 NTT used for voting.
    function initialize(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        IVotesUpgradeable _powerToken,
        NTToken _memberToken
    ) external initializer {
        __MajorityVotingBase_init(_dao, _votingSettings);

        votingPowerToken = _powerToken;
        membershipToken = _memberToken;

        emit MembershipContractAnnounced({definingContract: address(_memberToken)});
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == TOKEN_VOTING_INTERFACE_ID ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice getter function for the voting token.
    /// @dev public function also useful for registering interfaceId and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function getVotingPowerToken() public view returns (IVotesUpgradeable) {
        return votingPowerToken;
    }

    /// @notice getter function for the membership token.
    /// @dev public function also useful for registering interfaceId and for distinguishing from majority voting interface.
    /// @return The token used for determining membership.
    function getMembershipToken() public view returns (NTToken) {
        return membershipToken;
    }

    /// @inheritdoc MajorityVotingBase
    function totalVotingPower(uint256 _blockNumber) public view override returns (uint256) {
        return votingPowerToken.getPastTotalSupply(_blockNumber);
    }

    /// @inheritdoc MajorityVotingBase
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) external override returns (uint256 proposalId) {
        uint256 snapshotBlock;
        unchecked {
            snapshotBlock = block.number - 1;
        }

        uint256 totalVotingPower_ = totalVotingPower(snapshotBlock);

        if (totalVotingPower_ == 0) {
            revert NoVotingPower();
        }
        //TODO: does this need to be in the form of getPastVotes / IVotesUpgradeable considering there is no delegate system and therefore no need for checking checkpoint voting history stored on chain
        if (membershipToken.balanceOf(_msgSender()) == 0) { 
            revert ProposalCreationForbidden(_msgSender());
        }

        if (votingPowerToken.getPastVotes(_msgSender(), snapshotBlock) < minProposerVotingPower()) {
            revert ProposalCreationForbidden(_msgSender());
        }

        proposalId = _createProposal({
            _creator: _msgSender(),
            _metadata: _metadata,
            _startDate: _startDate,
            _endDate: _endDate,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap
        });

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        (proposal_.parameters.startDate, proposal_.parameters.endDate) = _validateProposalDates(
            _startDate,
            _endDate
        );
        proposal_.parameters.snapshotBlock = snapshotBlock.toUint64();
        proposal_.parameters.votingMode = votingMode();
        proposal_.parameters.supportThreshold = supportThreshold();
        proposal_.parameters.minVotingPower = _applyRatioCeiled(
            totalVotingPower_,
            minParticipation()
        );

        // Reduce costs
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length; ) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        if (_voteOption != VoteOption.None) {
            vote(proposalId, _voteOption, _tryEarlyExecution);
        }
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return membershipToken.balanceOf(_account) > 0;
    }

    /// @inheritdoc MajorityVotingBase
    function _vote(
        uint256 _proposalId,
        VoteOption _voteOption,
        address _voter,
        bool _tryEarlyExecution
    ) internal override {
        Proposal storage proposal_ = proposals[_proposalId];

        // This could re-enter, though we can assume the governance token is not malicious
        uint256 votingPower = votingPowerToken.getPastVotes(_voter, proposal_.parameters.snapshotBlock);
        VoteOption state = proposal_.voters[_voter];

        // If voter had previously voted, decrease count
        if (state == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes - votingPower;
        } else if (state == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no - votingPower;
        } else if (state == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain - votingPower;
        }

        // write the updated/new vote for the voter.
        if (_voteOption == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes + votingPower;
        } else if (_voteOption == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no + votingPower;
        } else if (_voteOption == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain + votingPower;
        }

        proposal_.voters[_voter] = _voteOption;

        emit VoteCast({
            proposalId: _proposalId,
            voter: _voter,
            voteOption: _voteOption,
            votingPower: votingPower
        });

        if (_tryEarlyExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }

    /// @inheritdoc MajorityVotingBase
    function _canVote(
        uint256 _proposalId,
        address _account,
        VoteOption _voteOption
    ) internal view override returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // The voter votes `None` which is not allowed.
        if (_voteOption == VoteOption.None) {
            return false;
        }

        // The voter has no voting power.
        if (votingPowerToken.getPastVotes(_account, proposal_.parameters.snapshotBlock) == 0) {
            return false;
        }

        // The voter has no membership.
        if (membershipToken.balanceOf(_account) == 0) {
            return false;
        }

        // The voter has already voted but vote replacment is not allowed.
        if (
            proposal_.voters[_account] != VoteOption.None &&
            proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return false;
        }

        return true;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[49] private __gap;
}
