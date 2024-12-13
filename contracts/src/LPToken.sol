// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PositionManager is ERC721 {
    struct Position {
        address token0;
        address token1;
        uint256 liquidity;
        uint256 amount0;
        uint256 amount1;
        uint256 createdAt;
    }

    mapping(uint256 => Position) public positions; // tokenId => Position
    mapping(bytes32 => uint256) public poolTotalLiquidity; // poolId => total de la liquidité

    event PositionMinted(uint256 indexed tokenId, address indexed owner, address token0, address token1, uint256 liquidity);
    event PositionBurned(uint256 indexed tokenId, address indexed owner);
    event LiquidityAdded(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor() ERC721("PositionManager", "POS") {}

    /**
     * @notice Mint un NFT représentant la position de liquidité
     */
    function mintPosition(address token0, address token1, uint256 amount0, uint256 amount1) external {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        uint256 liquidity = sqrt(amount0 * amount1);

        // Enregistre la position du NFT
        positions[tokenId] = Position({
            token0: token0,
            token1: token1,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1,
            createdAt: block.timestamp
        });

        bytes32 poolId = keccak256(abi.encodePacked(token0, token1));
        poolTotalLiquidity[poolId] += liquidity;

        _mint(msg.sender, tokenId);

        emit PositionMinted(tokenId, msg.sender, token0, token1, liquidity);
    }

    /**
     * @notice Brûle un NFT et retire la liquidité correspondante
     */
    function burnPosition(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Vous n'êtes pas le propriétaire du NFT");

        Position memory position = positions[tokenId];
        bytes32 poolId = keccak256(abi.encodePacked(position.token0, position.token1));

        // Met à jour la liquidité totale du pool
        poolTotalLiquidity[poolId] -= position.liquidity;

        // Supprime la position
        delete positions[tokenId];

        // Brûle le NFT
        _burn(tokenId);

        emit PositionBurned(tokenId, msg.sender);
    }

    /**
     * @notice Ajoute de la liquidité à une position existante
     */
    function addLiquidity(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        require(ownerOf(tokenId) == msg.sender, "Vous n'êtes pas le propriétaire du NFT");

        Position storage position = positions[tokenId];
        uint256 newLiquidity = sqrt(amount0 * amount1);

        position.liquidity += newLiquidity;
        position.amount0 += amount0;
        position.amount1 += amount1;

        bytes32 poolId = keccak256(abi.encodePacked(position.token0, position.token1));
        poolTotalLiquidity[poolId] += newLiquidity;

        emit LiquidityAdded(tokenId, amount0, amount1);
    }

    /**
     * @notice Fonction utilitaire pour calculer la racine carrée
     */
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
