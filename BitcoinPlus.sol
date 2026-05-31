// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BitcoinPlus (BTCP)
 * @dev Token con impuesto automático del 0.05% enviado a Tesorería.
 * Características mejoradas: pausable, seguro contra reentrancia, eventos de auditoría.
 */
contract BitcoinPlus is ERC20, ERC20Pausable, Ownable, ReentrancyGuard {
    // Tu dirección de Caja Fuerte (Tesorería)
    address public constant TREASURY = 0xfbA81320566CEb0D9C2B47a49421847D0cd7b515;
    
    // Tasa de impuesto: 5 sobre 10000 = 0.05%
    uint256 public constant TAX_RATE = 5;
    
    // Divisor para cálculos de impuesto
    uint256 private constant TAX_DIVISOR = 10000;

    // Evento para auditoría de impuestos
    event TaxApplied(address indexed from, address indexed to, uint256 amount, uint256 taxAmount);
    
    // Evento para cambios de tesorería (si se permite delegación futura)
    event TreasuryUpdated(address indexed newTreasury);

    constructor() ERC20("Bitcoin Plus", "BTCP") Ownable(msg.sender) {
        // Suministro inicial: 1,000,000 monedas
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /**
     * @dev Pausa las transferencias (solo owner)
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Reanuda las transferencias (solo owner)
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Función que se ejecuta en cada transferencia.
     * Aplica el impuesto automáticamente (0.05%).
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) whenNotPaused {
        // Validaciones básicas
        require(amount > 0, "Amount must be greater than 0");
        require(to != address(0), "Cannot transfer to zero address");

        // Aplicar impuesto si es una transferencia normal
        // NO aplicar impuesto si:
        // - Es mint (from == address(0))
        // - Envía desde o hacia la tesorería
        if (from != address(0) && to != TREASURY && from != TREASURY) {
            uint256 taxAmount = (amount * TAX_RATE) / TAX_DIVISOR;
            uint256 finalAmount = amount - taxAmount;

            // Verificar que el usuario tenga suficiente balance
            require(balanceOf(from) >= amount, "Insufficient balance");

            // Transferencia con impuesto
            super._update(from, to, finalAmount);
            super._update(from, TREASURY, taxAmount);

            // Emitir evento de auditoría
            emit TaxApplied(from, to, finalAmount, taxAmount);
        } else {
            // Transferencia sin impuesto (mint, burn, o relacionada con tesorería)
            super._update(from, to, amount);
        }
    }

    /**
     * @dev Permite al owner retirar tokens acumulados en la tesorería
     * (en caso de que se necesite realizar acciones con los fondos)
     */
    function withdrawTaxes(uint256 amount) public onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(TREASURY) >= amount, "Insufficient taxes collected");
        
        _update(TREASURY, msg.sender, amount);
    }

    /**
     * @dev Retorna la cantidad total de impuestos acumulados
     */
    function getTotalTaxesCollected() public view returns (uint256) {
        return balanceOf(TREASURY);
    }

    /**
     * @dev Retorna la tasa de impuesto actual
     */
    function getTaxRate() public pure returns (uint256) {
        return TAX_RATE;
    }

    /**
     * @dev Calcula el impuesto para una cantidad dada
     */
    function calculateTax(uint256 amount) public pure returns (uint256) {
        return (amount * TAX_RATE) / TAX_DIVISOR;
    }

    /**
     * @dev Quema tokens (reduce suministro total)
     */
    function burn(uint256 amount) public {
        _update(msg.sender, address(0), amount);
    }

    /**
     * @dev Quema tokens de una dirección específica (solo owner)
     */
    function burnFrom(address account, uint256 amount) public onlyOwner {
        _update(account, address(0), amount);
    }
}
