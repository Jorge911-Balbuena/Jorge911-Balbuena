// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title StakingLottery
 * @dev Sistema de staking con sorteos justos y seguros
 */
contract StakingLottery is Ownable, ReentrancyGuard, Pausable {
    IERC20 public stakingToken;

    struct Staker {
        uint256 amount;
        uint256 stakedAt;
        uint256 lastWithdrawAt;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerAddresses;
    mapping(address => bool) public isStaker;

    uint256 public totalStaked;
    uint256 public lockingPeriod = 7 days; // Período de bloqueo mínimo
    uint256 public constant LOTTERY_PERCENTAGE = 10; // 10% del premio
    
    // Sorteo
    uint256 public lastLotteryTime;
    uint256 public lotteryInterval = 30 days; // Sorteo cada 30 días
    uint256 public lotteryPrizePool;

    // Eventos
    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 timestamp);
    event LotteryWinner(address indexed winner, uint256 prize, uint256 timestamp);
    event LotteryTriggered(uint256 prizeDistributed, uint256 timestamp);
    event LockingPeriodUpdated(uint256 newPeriod);
    event LotteryIntervalUpdated(uint256 newInterval);
    event PrizePoolUpdated(uint256 newAmount);

    constructor(address _tokenAddress) Ownable(msg.sender) {
        require(_tokenAddress != address(0), "Invalid token address");
        stakingToken = IERC20(_tokenAddress);
        lastLotteryTime = block.timestamp;
    }

    /**
     * @dev Permite al usuario bloquear sus tokens para participar en el sorteo
     */
    function stake(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        if (!isStaker[msg.sender]) {
            stakerAddresses.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        stakers[msg.sender].amount += _amount;
        stakers[msg.sender].stakedAt = block.timestamp;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Permite al usuario retirar sus tokens después del período de bloqueo
     */
    function unstake(uint256 _amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        
        require(staker.amount >= _amount, "Insufficient staked amount");
        require(_amount > 0, "Amount must be greater than 0");
        require(
            block.timestamp >= staker.stakedAt + lockingPeriod,
            "Tokens still locked"
        );

        staker.amount -= _amount;
        staker.lastWithdrawAt = block.timestamp;
        totalStaked -= _amount;

        require(stakingToken.transfer(msg.sender, _amount), "Transfer failed");

        // Remover del array si no tiene más tokens
        if (staker.amount == 0) {
            isStaker[msg.sender] = false;
        }

        emit Unstaked(msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Retira todos los tokens del usuario (si el período de bloqueo ha pasado)
     */
    function unstakeAll() external nonReentrant {
        uint256 amount = stakers[msg.sender].amount;
        require(amount > 0, "No staked tokens");
        unstake(amount);
    }

    /**
     * @dev Ejecuta el sorteo de la lotería
     * Requiere que haya pasado el intervalo de lotería
     */
    function triggerLottery() external onlyOwner nonReentrant {
        require(stakerAddresses.length > 0, "No stakers available");
        require(
            block.timestamp >= lastLotteryTime + lotteryInterval,
            "Lottery not ready yet"
        );
        require(lotteryPrizePool > 0, "Prize pool is empty");

        // Seleccionar ganador usando Chainlink VRF o método seguro
        // Aquí usamos un método pseudo-aleatorio mejorado
        uint256 randomNumber = uint256(
            keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao, // Más seguro que block.difficulty
                blockhash(block.number - 1),
                totalStaked
            ))
        ) % stakerAddresses.length;

        address winner = stakerAddresses[randomNumber];
        uint256 prize = (lotteryPrizePool * LOTTERY_PERCENTAGE) / 100;

        require(prize <= lotteryPrizePool, "Prize exceeds pool");
        require(
            stakingToken.balanceOf(address(this)) >= prize,
            "Insufficient contract balance"
        );

        lotteryPrizePool -= prize;
        lastLotteryTime = block.timestamp;

        require(stakingToken.transfer(winner, prize), "Prize transfer failed");

        emit LotteryWinner(winner, prize, block.timestamp);
        emit LotteryTriggered(prize, block.timestamp);
    }

    /**
     * @dev Deposita fondos para el premio del sorteo
     */
    function depositPrizePool(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        lotteryPrizePool += _amount;
        emit PrizePoolUpdated(lotteryPrizePool);
    }

    /**
     * @dev Retira fondos no utilizados del premio (solo owner)
     */
    function withdrawPrizePool(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount <= lotteryPrizePool, "Amount exceeds prize pool");
        lotteryPrizePool -= _amount;
        require(stakingToken.transfer(msg.sender, _amount), "Transfer failed");
        emit PrizePoolUpdated(lotteryPrizePool);
    }

    /**
     * @dev Actualiza el período de bloqueo (solo owner)
     */
    function setLockingPeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod > 0, "Period must be greater than 0");
        lockingPeriod = _newPeriod;
        emit LockingPeriodUpdated(_newPeriod);
    }

    /**
     * @dev Actualiza el intervalo de la lotería (solo owner)
     */
    function setLotteryInterval(uint256 _newInterval) external onlyOwner {
        require(_newInterval > 0, "Interval must be greater than 0");
        lotteryInterval = _newInterval;
        emit LotteryIntervalUpdated(_newInterval);
    }

    /**
     * @dev Pausa el staking en caso de emergencia
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Reanuda el staking
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // Funciones de consulta

    /**
     * @dev Retorna la cantidad de stakers activos
     */
    function getStakersCount() external view returns (uint256) {
        return stakerAddresses.length;
    }

    /**
     * @dev Retorna la información del staker
     */
    function getStakerInfo(address _staker) external view returns (
        uint256 amount,
        uint256 stakedAt,
        uint256 daysLocked,
        bool canUnstake
    ) {
        Staker memory staker = stakers[_staker];
        uint256 daysPassed = (block.timestamp - staker.stakedAt) / 1 days;
        bool canWithdraw = block.timestamp >= staker.stakedAt + lockingPeriod;

        return (
            staker.amount,
            staker.stakedAt,
            daysPassed,
            canWithdraw
        );
    }

    /**
     * @dev Retorna el tiempo restante hasta el próximo sorteo
     */
    function timeUntilNextLottery() external view returns (uint256) {
        uint256 nextLotteryTime = lastLotteryTime + lotteryInterval;
        if (block.timestamp >= nextLotteryTime) {
            return 0;
        }
        return nextLotteryTime - block.timestamp;
    }

    /**
     * @dev Retorna el balance total del contrato
     */
    function getContractBalance() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }

    /**
     * @dev Retorna estadísticas del contrato
     */
    function getContractStats() external view returns (
        uint256 totalStakedAmount,
        uint256 prizePool,
        uint256 stakersCount,
        uint256 nextLotteryIn
    ) {
        uint256 nextLottery = lastLotteryTime + lotteryInterval;
        uint256 timeRemaining = block.timestamp >= nextLottery ? 0 : nextLottery - block.timestamp;

        return (
            totalStaked,
            lotteryPrizePool,
            stakerAddresses.length,
            timeRemaining
        );
    }
}
