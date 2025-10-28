# Stepwise-Streaming Systolic CNN Accelerator

### 📅 May 2025 – July 2025  
**Tools:** SystemVerilog, Synopsys (VCS, Verdi, Design Compiler), ARM SRAM Compiler, PyTorch  
**Target Process:** TSMC 40 nm  
**Performance:** 129 GFLOPs/s (INT8-equivalent) @ 500 MHz  
**Area:** 412.7 K µm²  

---

## 🧩 Overview

This project implements a **CNN accelerator ASIC** based on a **stepwise-streaming systolic array** architecture with **cached weight dataflow**.  
The design focuses on minimizing off-chip memory access through **cyclic weight reuse** within each Processing Element (PE), achieving high throughput and energy efficiency.

---

## 🚀 Key Features

- **Systolic Array Architecture:**  
  4 × 9 × 8 PE grid optimized for INT8 multiply–accumulate (MAC) operations.

- **Cached Weight Dataflow:**  
  Enables cyclic weight reuse within PEs, significantly reducing memory bandwidth demands.

- **Stepwise Streaming:**  
  Tiled activation scheduling ensures continuous streaming of feature maps and balanced PE utilization.

- **Fused MAC–ReLU–Max Units:**  
  On-chip fusion of compute and nonlinearity operations (MAC → ReLU → Max-pool) to reduce memory access overhead.

- **Quantized Model Deployment:**  
  End-to-end flow from **PyTorch model quantization** → **custom ISA compilation** → **RTL simulation**.

- **ASIC Implementation Flow:**  
  - RTL → Synthesis → Gate-level Simulation  
  - Tools: **Synopsys VCS**, **Design Compiler**, **Verdi**  
  - SRAM generated via **ARM SRAM Compiler**  
  - Technology: **TSMC 40 nm**

---

## 📊 Results

| Metric | Value | Notes |
|:--|:--|:--|
| Frequency | 500 MHz | Nominal TT / 1.1 V / 25 °C |
| Throughput | 129 GFLOPs/s | INT8-equivalent |
| Total Area | 412.7 K µm² | Post-synthesis |
| Model Tested | MNIST | Quantized 3×3 Conv + FC network |
| Verification | RTL + Post-synthesis simulation | Verdi waveform inspection |

---

## 🧠 Architecture Highlights

- **Processing Element (PE):**  
  Each PE performs multiply–accumulate and passes partial sums in a systolic fashion.  
  Cached weights are reused for multiple activation tiles.

- **On-Chip SRAM Buffering:**  
  Dual-bank SRAM buffers for activations and partial sums to support stepwise streaming.

- **Custom ISA Controller:**  
  Decouples activation load, compute, and output phases to reduce control overhead.

- **Dataflow Optimization:**  
  Activation tiling and scheduling ensure maximum array utilization for convolutional workloads.

---

## 🧪 Simulation and Verification

- RTL verification via **Synopsys VCS**
- Waveform debug with **Verdi**
- Post-synthesis verification using **Design Compiler**
- Testbench stimuli generated from **quantized PyTorch tensors**
- Output validated against reference software model

---

---

## 📚 References

- [Chen et al., “Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep CNNs,” ISSCC 2016]  
- [Kung, “Systolic Arrays for VLSI,” 1982]  
- [Synopsys Design Compiler User Guide]  

---

## 🧾 License

Due to copyright restrictions, this repository includes only the synthesis and simulation results.

---

### Author
**Chia-Heng Liu**  
M.Eng. ECE, Cornell University  
Email: [chialiu0618@gmail.com](mailto:chialiu0618@gmail.com)  
GitHub: [ChiaLiu0618](https://github.com/ChiaLiu0618)  
LinkedIn: [linkedin.com/in/chia-heng-liu-chialiu20020618](https://www.linkedin.com/in/chia-heng-liu-chialiu20020618)
