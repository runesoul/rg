# 📄 NodeCard 合约技术文档

## 合约概述

`NodeCard` 是一个用于管理购买节点卡(Node Card)的智能合约，基于 BNB Chain 实现，支持经由 Oracle 签名的代币支付购买操作，并支持 BNB 付费。

---

## 基本参数

| 参数                   | 含义                                                 |
| ---------------------- | ---------------------------------------------------- |
| `oracle`               | 用于验签的签名者地址，仅有该地址签名有效             |
| `vault`                | 资金收款地址，用于收到 ERC20 和 BNB                  |
| `BNB_FEE`              | 指定累计购买需支付的 BNB 手续费（默认 0.0001 ether） |
| `usedPurchaseContexts` | 已使用的购买上下文标识，用于防止重复                 |

---

## 核心逻辑

### 购买节点卡 `purchase()`

1. 校验 tokenAddrList 和 tokenAmountList 长度匹配
2. 校验购买未过期（比对 `deadline`）
3. 校验充足的 BNB 费用
4. 校验 `purchaseContext` 未被使用过
5. 解析 signature 得到 v, r, s
6. 构造签名模拟数据，并校验 oracle 是否是签名者
7. 对所有 tokenAddrList[i] 执行 `safeTransferFrom(msg.sender, vault, tokenAmountList[i])`
8. 将 BNB_FEE 转入 vault
9. 如果 msg.value > BNB_FEE，退还多余 BNB
10. 记录 purchaseContext 已使用，并 emit `NodeCardPurchased`

---

## 主要功能

### 签名校验

- 通过 ECDSA 验证用户提供的 signature 是否来自指定 oracle 地址
- 数据整合方式：`abi.encodePacked(user, tokenAddrList, tokenAmountList, purchaseContext, deadline)`

### 防重复

- `purchaseContext` 作为唯一标识，无法重复使用，防止重复和重收付

### 费用处理

- 需要支付指定的 `BNB_FEE`，上限多给部分退还

### 开放配置

- `setOracle` / `setVault` 可由 owner 配置 oracle 和 vault 地址
- `emergencyWithdraw` 允许 owner 抽离 vault 中的 token 或 BNB

---

## 事件

| 事件                | 含义                                                           |
| ------------------- | -------------------------------------------------------------- |
| `NodeCardPurchased` | 成功购买节点卡时触发，包含用户、token 列表、付费、timestamp 等 |
