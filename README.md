# Xpswap

**Xpswap** is a simple modern DEX, built using **Solidity**, **Foundry**, and **Next.js**. The project aims to recreate the core mechanics and some features of Uniswap V4, focusing on decentralized token swapping, liquidity pools, and automated market making (AMM). 


## **Design Approach for AMM**

The AMM design draws inspiration from recent advancements in decentralized exchange protocols, adopting more modular and flexible mechanisms compared to earlier models. By introducing features such as transient state tracking using EIP-1153 and dynamic liquidity adjustments, Xpswap enhances operational efficiency and scalability. These design choices reflect an evolution in AMM architecture, aligning with innovations seen in newer protocols like Uniswap V4. Unlike factory-centered architectures, Xpswap employs a monolithic contract design where all pools are managed within a single contract. This architecture enables centralized tracking of state variables, more cohesive logic, and reduced overhead compared to deploying a new contract for each liquidity pool. This approach ensures that liquidity provisioning and swaps are handled with greater precision, while also incorporating robust validation to maintain system integrity.


## **Project Status**
Currently under development — **Smart contracts are being written and tested**. The Next.js frontend and full integration with Foundry will be built after the smart contract logic is complete.

