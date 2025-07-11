# 📘 Runesoul 合约文档

## 合约简介

Runesoul 是一个多功能游戏资产管理合约，支持：

- 多种代币的充值/提现管理
- 用户提现请求审批（带 Oracle 签名校验）
- 支持用户自助添加/移除代币（支付 BNB 费用）
- 运营商可分发费用/更新 Merkle Root（用于奖励系统）
- 与 PancakeSwap 集成，用于奖励自动兑换和换回

## 🔑 权限控制

- `DEFAULT_ADMIN_ROLE`：部署者
- `OPERATOR_ROLE`：拥有操作权限的角色（可确认提现、设置 MerkleRoot 等）

---

## 🧾 核心结构体

### `struct Withdraw`

记录提现请求状态，包括是否已确认、已取消等。

### `struct TokenInfo`

存储支持的 token 配置（是否支持、最小充值量）。

### `struct PancakeSwapInfo`

支持换对 token 的地址及其配对 token 信息。

---

## 💰 充值与提现流程

### `deposit(token, amount)`

- 支持任意 `supportedTokens` 列表中的代币充值
- 满足最小充值量要求
- 资产进入合约，记录至 `playerDeposit`

### `withdrawRequest(token, amount)`

- 用户发起提现请求
- 每次请求需等待前一次确认/取消
- 存储到 `withdraws` 中，等待运营确认

### `withdrawConfirm(...)` & `withdrawCancel(...)`

- 需 `OPERATOR_ROLE` 权限
- 校验 Oracle 签名以确认请求有效
- 从合约中将资产发送给用户或标记请求为取消

---

## 🧾 用户代币管理（需要支付手续费）

- `userAddToken(token, minDeposit)`：用户自助添加代币（支付 `userTokenFee`）
- `userRemoveToken(token)`：用户自助移除代币
- 手续费转给 `feeWallet`

---

## 🏦 手续费处理

- 所有提现会扣除 `feePercent`（默认单位为 bps，万分制）
- 手续费发往 `feeWallet`
- 支持 `distributeFee(...)` 将手续费从合约打入 `distributeAddress`

---

## 🥞 PancakeSwap 套利奖励相关

- `mintPairedToken(...)`：兑换并记录用户收益
- `claimPairedTokenRewards(...)`：从奖励 token 中提取部分进行套利操作并换回主 token

---

## 🌲 Merkle Root 奖励管理

- 支持 `setMerkleRoot(...)` 由运营人员签名控制
- `verifyMerkleProof(...)` 提供链上验证功能

---

## 📌 重要参数

| 参数                | 说明                                                      |
| ------------------- | --------------------------------------------------------- |
| `oracle`            | 签名验证者地址（控制提现、分发等关键操作）                |
| `feeWallet`         | 手续费收款地址                                            |
| `distributeAddress` | 用于分发奖励的地址                                        |
| `merkleRoot`        | 当前生效的奖励校验根                                      |
| `userTokenFee`      | 用户添加自定义代币时需要支付的 BNB 费用（默认 0.5 ether） |

---

## 🧠 安全机制

- 所有关键操作通过 Oracle 签名确认
- 所有用户提现需先请求，等待运营确认
- 角色权限明确划分（Owner vs Operator）
