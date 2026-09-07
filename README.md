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

- RTL verification performed using **Synopsys VCS**  
- Waveform debugging and signal tracing with **Verdi**  
- Post-synthesis functional verification using **Design Compiler**  
- Testbench stimuli generated from **quantized PyTorch tensors**  
- Output results matched against a **reference software model** to ensure functional correctness  
- Deployed the accelerator on a **quantized MNIST inference task**, demonstrating correct end-to-end mapping from software model to hardware execution

---

---

## 📚 References

[1] Y.-H. Chen, T. Krishna, J. S. Emer, and V. Sze,  
“**Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks**,”  
*IEEE Journal of Solid-State Circuits*, vol. 52, no. 1, pp. 127–138, Jan. 2017.  
DOI: [10.1109/JSSC.2016.2616357](https://doi.org/10.1109/JSSC.2016.2616357)

[2] N. P. Jouppi *et al.*,  
“**In-Datacenter Performance Analysis of a Tensor Processing Unit**,”  
*Proceedings of the 44th Annual International Symposium on Computer Architecture (ISCA)*, pp. 1–12, 2017.  
DOI: [10.1145/3079856.3080246](https://doi.org/10.1145/3079856.3080246)

[3] Xilinx Inc.,  
“**DPUCADX8G IP Core Product Brief: Deep Learning Processor Unit (DPU) for Alveo U200/U250**,”  
2020. [Online]. Available: [https://docs.amd.com/r/1.2-English/ug1414-vitis-ai/Alveo-U200/U250-DPUCADX8G](https://docs.amd.com/r/1.2-English/ug1414-vitis-ai/Alveo-U200/U250-DPUCADX8G)

---

## Source files and simulation inputs

The `Accelerator/` directory contains the SystemVerilog RTL and testbenches.
`Accelerator/Neural_Network/` also contains the input image and quantized weights.

Run the layer testbenches from `Accelerator/Neural_Network/` in this order: `tb_CONV1`, `tb_CONV2`, `tb_CONV3`, then `tb_FC`. Each convolution testbench writes feature-map text files consumed by the next layer. These generated maps are excluded from version control.

Technology libraries, SRAM compiler files, tool configuration, generated binaries, waveforms, reports, and logs are excluded. The `.gitignore` explicitly allows only the reviewed source and input files, plus this README and the ignore rules.

---

### Author
**Chia-Heng Liu**  
M.Eng. ECE, Cornell University  
Email: [chialiu0618@gmail.com](mailto:chialiu0618@gmail.com)  
GitHub: [ChiaLiu0618](https://github.com/ChiaLiu0618)  
LinkedIn: [linkedin.com/in/chia-heng-liu-chialiu20020618](https://www.linkedin.com/in/chia-heng-liu-chialiu20020618)
