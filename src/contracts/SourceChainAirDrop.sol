// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainAirdropSender is OwnerIsCreator { // OwnerIsCreator is the base class
    // 目标链的链ID (Chainlink定义的ID，不是实际链ID)
    uint64 private destinationChainSelector;
    // 目标链上的接收合约地址
    address private receiverContract;
    // 用于支付CCIP费用的代币
    address private linkToken;
    address private s_router;

    constructor(
        address _router,
        uint64 _destinationChainSelector,
        address _receiverContract,
        address _linkToken
    ) { // Removed CCIPReceiver(_router) call
        // OwnerIsCreator's constructor (if any, usually implicit) is called automatically.
        s_router = _router;
        destinationChainSelector = _destinationChainSelector;
        receiverContract = _receiverContract; 
        linkToken = _linkToken;
    }
    
    // 发起跨链空投
    function initiateAirdrop(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "Length mismatch");
        
        // 编码跨链消息
        bytes memory data = abi.encode(recipients, amounts);
        
        // 构建CCIP消息
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverContract),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: linkToken
        });

        // 获取费用估算
        uint256 fee = IRouterClient(s_router).getFee(
            destinationChainSelector,
            message
        );
        
        // 确保合约有足够的LINK代币支付费用
        require(IERC20(linkToken).balanceOf(address(this)) >= fee, "Not enough LINK");
        
        // 批准Router使用LINK代币
        IERC20(linkToken).approve(s_router, fee);
        
        // 发送跨链消息
        bytes32 messageId = IRouterClient(s_router).ccipSend(
            destinationChainSelector,
            message
        );
        
        emit MessageSent(messageId, destinationChainSelector, receiverContract, data);
    }
    
    // 更新目标链信息
    function updateDestination(
        uint64 _destinationChainSelector,
        address _receiverContract
    ) external onlyOwner {
        destinationChainSelector = _destinationChainSelector;
        receiverContract = _receiverContract;
    }
    
    // 提取合约中的代币（紧急情况使用）
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
    
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        bytes data
    );
}