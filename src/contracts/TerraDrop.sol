// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol"; // 用于 Keeper 兼容;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // 或者使用 ConfirmedOwner

contract TerraDrop is VRFConsumerBaseV2, ConfirmedOwner { // 根据需要继承

    // --- 状态变量 ---
    // address public owner;
    LinkTokenInterface internal LINK_TOKEN;
    address internal VRF_COORDINATOR;
    bytes32 internal KEY_HASH; // VRF Key Hash
    uint64 internal s_subscriptionId; // VRF Subscription ID
    uint32 internal callbackGasLimit; // VRF 回调的 Gas 限制

    // 事件定义结构体
    struct EventTrigger {
        uint256 eventId;
        string eventDescription;
        // ... 其他条件，例如 API 端点，预期值等
        bool isActive;
    }
    mapping(uint256 => EventTrigger) public eventTriggers;
    uint256 public nextEventId;

    // 用户资格结构体
    struct UserQualification {
        bool isRegistered;
        uint256 stakedAmount; // 示例：质押数量
        // ... 其他资格条件
    }
    mapping(address => UserQualification) public userQualifications;
    address[] public registeredUsers;

    // 空投代币
    IERC20 public airdropToken;

    // Chainlink Functions 相关变量
    address public functionsOracle;
    bytes32 public functionsJobId;
    uint256 public functionsFee;
    uint256 public s_lastEventId;
    // --- 事件 ---
    event NewEventTriggerDefined(uint256 indexed eventId, string description);
    event EventTriggered(uint256 indexed eventId, string description);
    event UserRegistered(address indexed user);
    event WinnersSelected(uint256 indexed eventId, address[] winners, uint256[] amounts);
    event AirdropClaimed(address indexed user, uint256 amount);

    // --- 修改器 ---
    // modifier onlyOwner() override{
    //     require(owner == msg.sender, "Not the owner");
    //     _;
    // }

    modifier onlyFunctionsOracle() { // 用于限制 Chainlink Functions 的调用
        require(msg.sender == functionsOracle, "Caller is not the Functions Oracle");
        _;
    }

    // --- 构造函数 ---
    constructor(
         address _vrfCoordinator, 
         address _link, 
         uint64 _subscriptionId,
          bytes32 _keyHash, 
          address _airdropTokenAddress
        )  VRFConsumerBaseV2(_vrfCoordinator) ConfirmedOwner(msg.sender)  {
        // owner = msg.sender;
        LINK_TOKEN = LinkTokenInterface(_link);
        VRF_COORDINATOR = _vrfCoordinator;
        s_subscriptionId = _subscriptionId;
        KEY_HASH = _keyHash;
        airdropToken = IERC20(_airdropTokenAddress);
        nextEventId = 1;
    }

    // --- 管理员功能 ---
    function defineEventTrigger(string memory _description /*, ... other params */) public onlyOwner {
        eventTriggers[nextEventId] = EventTrigger(nextEventId, _description, true);
        emit NewEventTriggerDefined(nextEventId, _description);
        nextEventId++;
    }

    function updateEventTriggerStatus(uint256 _eventId, bool _isActive) public onlyOwner {
        require(eventTriggers[_eventId].eventId != 0, "Event not found");
        eventTriggers[_eventId].isActive = _isActive;
    }

    function setFunctionsOracle(address _oracle, bytes32 _jobId, uint256 _fee) public onlyOwner {
        functionsOracle = _oracle;
        functionsJobId = _jobId;
        functionsFee = _fee;
    }

    // --- 用户功能 ---
    function registerForAirdrop() public {
        require(!userQualifications[msg.sender].isRegistered, "Already registered");
        // TODO: 可能需要检查用户是否满足基本注册条件
        userQualifications[msg.sender].isRegistered = true;
        registeredUsers.push(msg.sender);
        emit UserRegistered(msg.sender);
    }

    // --- Chainlink Functions 回调 ---
    // function handleOracleResponse(
    //     bytes32 requestId, // Chainlink Functions 请求 ID
    //     bytes memory response, // Functions 返回的数据
    //     bytes memory err // Functions 错误信息
    // ) internal /* override */ {
    //     // require(msg.sender == functionsOracle, "Source must be the oracle");
    //     // require(err.length == 0, string(abi.encodePacked("Functions Error: ", err)));
    //     // 1. 解析 response，检查是否满足某个 EventTrigger 的条件
    //     // uint256 triggeredEventId = parseAndVerifyEvent(response);
    //     // if (triggeredEventId != 0 && eventTriggers[triggeredEventId].isActive) {
    //     //     emit EventTriggered(triggeredEventId, eventTriggers[triggeredEventId].eventDescription);
    //     //     // 2. 如果事件触发，请求 VRF
    //     //     requestRandomWinners(triggeredEventId);
    //     // }
    // }

    // --- Chainlink VRF 功能 ---
    // function requestRandomWinners(uint256 _eventId) internal returns (uint256 requestId) {
    //     // require(LINK_TOKEN.balanceOf(address(this)) >= functionsFee, "Not enough LINK"); // 假设 VRF 也用 LINK
    //     // return requestRandomWords(KEY_HASH, s_subscriptionId, 3, 10, 3); // 示例参数
    // }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        // 1. 根据 _randomWords 和合格用户列表 (qualifiedUsers) 抽取获奖者
        address[] memory winners = selectWinners(getQualifiedUsers(), _randomWords);
        uint256[] memory amounts = determineAmounts(winners.length, _randomWords); // 示例
        emit WinnersSelected(s_lastEventId, winners, amounts);
        // 2. 执行空投
        distributeAirdrop(winners, amounts);
    }

    // --- 空投逻辑 ---
    function getQualifiedUsers() internal view returns (address[] memory) {
        // 从 registeredUsers 中筛选出满足当前空投资格的用户
        // ... 实现筛选逻辑 ...
        return registeredUsers; // 简化版
    }

    function selectWinners(address[] memory _qualifiedUsers, uint256[] memory _randomWords) internal pure returns (address[] memory) {
        // ... 使用随机数从 _qualifiedUsers 中选择获奖者 ...
        return _qualifiedUsers; // 简化版
    }

    function determineAmounts(uint256 _numWinners, uint256[] memory _randomWords) internal pure returns (uint256[] memory) {
        // ... 根据随机数或规则确定每个获奖者的奖励数量 ...
        uint256[] memory amounts = new uint256[](_numWinners);
        for(uint i = 0; i < _numWinners; i++) {
            amounts[i] = 100 * 10**18; // 示例：固定数量
        }
        return amounts;
    }

    function distributeAirdrop(address[] memory _winners, uint256[] memory _amounts) internal {
        // require(_winners.length == _amounts.length, "Mismatch in winners and amounts");
        // for (uint i = 0; i < _winners.length; i++) {
        //     // TODO: 如果需要 CCIP，这里会更复杂
        //     // require(airdropToken.transfer(_winners[i], _amounts[i]), "Airdrop transfer failed");
        //     emit AirdropClaimed(_winners[i], _amounts[i]);
        // }
    }

    // --- CCIP 相关功能 (占位) ---
    function sendTokensToOtherChain(address _destinationChainSelector, address _receiver, address _token, uint256 _amount) internal {
        // ... 实现 CCIP 消息发送和代币转移逻辑 ...
    }

    // --- Getter 函数 (示例) ---
    function getEventTrigger(uint256 _eventId) public view returns (EventTrigger memory) {
        return eventTriggers[_eventId];
    }

    function getUserQualification(address _user) public view returns (UserQualification memory) {
        return userQualifications[_user];
    }

    // --- 接收 LINK (如果需要) ---
    // function receiveApproval(address _sender, uint256 _amount, address _token, bytes memory _data) external {
    //     // 用于接收 LINK 并触发 Chainlink Functions 调用 (如果使用此模式)
    // }
}