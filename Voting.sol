// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

/**
 * L'admin fait évoluer le statut du vote avec la fonction setWorkflowStatus.
 * Un contrôle empêche de revenir à un statut antérieur.
 * Il est possible de revenir à l'état initial avec la fonction resetVote.
 * Le passage au statut VotesTallied n'est pas manuel, il est assuré par la fonction setWinningProposalId,
 * lorsque l'admin a comptabilisé les votes.
 */

contract Voting is Ownable {

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    
    struct Proposal {
        string description;
        uint voteCount;  
    }

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    mapping(address => Voter) voters;

    Proposal[] proposals;
    
    uint winningProposalId;
    
    WorkflowStatus currentWorkflowStatus; 

    address[] votersAddresses; // Optionnel - permet de réinitialiser les propriétés des Voters par défaut

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted(address voter, uint proposalId);
    event ResetVote(uint, WorkflowStatus previousStatus); // Optionnel

    constructor() {
        // L'administrateur est considéré comme un électeur afin lui garantir l'accès aux fonctionnalités des Voters
        voters[msg.sender] = Voter(true, false, 0);
    }

    modifier onlyVoterRegistered() {
        require(voters[msg.sender].isRegistered == true, "Not allowed : you are not registered");
        _;
    }

    /**
     * Optionnel
     * Retourne true si la description est retrouvée parmi les propositions déjà enregistrées
     */
    function proposalDescriptionExists(string calldata _proposalDescription) private view returns (bool) {
        bool found;
        for (uint i = 0; i < proposals.length; i++) {
            if (keccak256(abi.encodePacked(proposals[i].description)) == keccak256(abi.encodePacked(_proposalDescription))) {
                found = true;
                break;
            }
        }
        return found;
    }

    /**
     * L'administrateur du vote met à jour l'état du vote
     * Seul le passage au statut VotesTallied ne peut être effectué manuellement, il est assuré par la fonction setWinningProposalId
     */
    function setWorkflowStatus(WorkflowStatus _workflowStatus) public onlyOwner {
        require(_workflowStatus > currentWorkflowStatus, "you cannot go back to a previous status, in case of problem you have to reset the vote process");
        WorkflowStatus previousWorkflowStatus = currentWorkflowStatus;
        currentWorkflowStatus = _workflowStatus;
        emit WorkflowStatusChange(previousWorkflowStatus, currentWorkflowStatus);
    }

    /**
     * Optionnel
     * L'administrateur peut réinitialiser le processus de vote
     */
    function resetVote() public onlyOwner {
        // Stockage du statut en cours pour l'event
        WorkflowStatus previousWorkflowStatus = currentWorkflowStatus;

        // Réinitialisation du statut
        currentWorkflowStatus = WorkflowStatus.RegisteringVoters;

        // Suppression des propositions
        delete proposals;

        // Réinitialisation de la proposition gagnante
        winningProposalId = 0;

        // Réinitialisation des propriétés des Voters (à part la propriété isRegistered de l'administrateur)
        for (uint i = 0; i < votersAddresses.length; i++) {
            if (votersAddresses[i] != owner()) {
                voters[votersAddresses[i]].isRegistered = false;
            } 
            voters[votersAddresses[i]].isRegistered = false;
            voters[votersAddresses[i]].votedProposalId = 0;
        }

        emit ResetVote(block.timestamp, previousWorkflowStatus);  
    } 

    /**
     * L'administrateur du vote peut consulter le statut en cours
     */
    function getWorkflowStatus() external view onlyOwner returns (WorkflowStatus) {
        return currentWorkflowStatus;
    }

    /**
     * Point 1
     * L'administrateur du vote enregistre une liste blanche d'électeurs identifiés par leur adresse Ethereum
     */
    function registerVoter(address _address) external onlyOwner {
        require(currentWorkflowStatus == WorkflowStatus.RegisteringVoters, "you can set voter only during the registering period");
        require(voters[_address].isRegistered != true, "already registered");
        Voter memory voter = Voter(true, false, 0);
        voters[_address] = voter;
        
        emit VoterRegistered(_address);
    }

    /**
     * Retourne un user à partir de son adresse
     */
    function getVoter(address _address) external view onlyOwner returns (Voter memory) {
        return voters[_address];
    }

    /**
     * Retourne la proposition votée par l'électeur à partir de son adresse
     * Le vote n'est pas secret pour les utilisateurs ajoutés à la Whitelist
     */
    function getVoterVotedProposal(address _address) external view onlyVoterRegistered returns (Proposal memory) {
        require(voters[_address].hasVoted, "voter has not voted yet");
        return proposals[voters[_address].votedProposalId];
    }

    /**
     * Point 3
     * Les électeurs inscrits sont autorisés à enregistrer leurs propositions pendant que la session d'enregistrement est active
     */
    function registerProposal(string calldata _description) external onlyVoterRegistered {
        require(currentWorkflowStatus == WorkflowStatus.ProposalsRegistrationStarted, "You can only register a proposal during registration period");
        require(!proposalDescriptionExists(_description), "The proposal description you have submitted already exists");
        Proposal memory proposal = Proposal(_description, 0);
        proposals.push(proposal);

        // C'est l'index de la proposition qui est utilisé comme identifiant unique
        emit ProposalRegistered(proposals.length-1);
    }

    /**
     * Point 6
     * Les électeurs inscrits votent pour leur proposition préférée
     */
    function voteProposal(uint _proposalId) external onlyVoterRegistered {
        require(currentWorkflowStatus == WorkflowStatus.VotingSessionStarted, "You can only vote for a proposal during the voting session");
        require(voters[msg.sender].hasVoted == false, "You have already voted");
        
        voters[msg.sender].votedProposalId = _proposalId;
        voters[msg.sender].hasVoted = true;

        // Incrémentation du nombre de vote pour la proposition
        proposals[_proposalId].voteCount++;

        if (proposals[_proposalId].voteCount > proposals[winningProposalId].voteCount) {
            winningProposalId = _proposalId;
        }

        emit Voted(msg.sender, _proposalId);
    }

    /**
     * Point 10
     * Tout le monde peut vérifier les derniers détails de la proposition gagnante
     * Retourne la description de la proposition gagnante
     */
    function getWinningProposalDescription() external view returns (string memory) {
        require(currentWorkflowStatus == WorkflowStatus.VotesTallied, "You can only consult the winning proposition description when votes have been counted");
        return proposals[winningProposalId].description;
    }

    /**
     * Point 10
     * Tout le monde peut vérifier les derniers détails de la proposition gagnante
     * Retourne la proposition gagnante
     */
    function getWinningProposal() external view returns (Proposal memory) {
        require(currentWorkflowStatus == WorkflowStatus.VotesTallied, "You can only consult the winning proposition when votes have been counted");
        return proposals[winningProposalId];
    }

    /**
     * Retourne la liste des propositions
     * Prérequis : électeurs whitelistés peuvent consulter la liste des propositions
     */
     function getProposals() external view onlyVoterRegistered returns (Proposal[] memory) {
        return proposals;
     }
 
}