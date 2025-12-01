# GNSS_generator

MATLAB-based generator of synthetic GNSS + jamming IQ tiles, designed to emulate the RF conditions from the **Jammertest 2023** campaign and to feed machine-learning pipelines (for example, the `GNSS-jamming-classifier` project).

> **Credits / origin**
>
> - This project is **heavily based on and originally derived from**  
>   **Dani Pascual**’s repository **GNSS-matlab**: <https://github.com/danipascual/GNSS-matlab>.  
>   Many GNSS signal generation functions and core ideas come from that work.
> - On top of GNSS-matlab, this repository adds:
>   - A configurable **GNSS + jammer + channel + RF front-end** simulator tailored to Jammertest-like scenarios.
>   - A dataset builder (`signal_generation_jammertest.m`) that produces stratified TRAIN/VAL/TEST sets of IQ tiles with rich metadata for machine learning.

---

## 1. Features

- **GNSS-like baseband generator**
  - Multi-channel GNSS-like signal at **60 MHz** sampling:
    - Uses `Fct_Channel_Gen.m` + helpers to produce a sum of several C/A-like PRN channels.
    - Parameter `ParamGNSS.SV_Number` controls the number of simulated satellites.
  - Bands are abstracted as `'L1CA'`, `'L2C'`, `'L5'`, `'E1OS'` (mapped internally to RF centre frequencies and bandwidths).

- **Realistic jammer models**
  - Jammers implemented in `Jammer_signals/`:
    - `jam_chirp.m` – chirp / sweep jammers (e.g. cigarette-lighter, USB, handheld multiband).
    - `jam_nb_prn.m` – narrowband PRN-like jamming.
    - `jam_wb_prn.m` – wideband PRN-like jamming.
    - `jam_cw.m` – continuous-wave (CW) tone jamming.
    - `jam_fh.m` – simple frequency-hopping model.
    - `jam_none.m` – no-jammer placeholder.
    - `jammer_factory.m` – central factory that maps **logical jammer classes** (e.g. `Chirp`, `NB`, `WB`) and **families** (e.g. `USB`, `CigS1`, `H3_3`) to physical parameters:
      - Jamming **bandwidth** (Hz).
      - **Centre frequency** (RF band).
      - **Sweep period** (for chirps).
      - Multiband combinations (for example, L1 + L2 + L5).

- **Channel and C/N0 + JSR control**
  - `Channel/` implements a simple baseband channel with:
    - AWGN controlled by **C/N0** (dB-Hz) per sample.
    - Optional Nakagami and Clarke-like fading helpers (for future use).
  - JSR (jammer-to-signal power ratio) is enforced in-band:
    - `scale_to_jsr.m` and logic inside `Fct_Channel_Gen.m` rescale jammer power for a given **JSR_dB**.
  - C/N0 and JSR are drawn from **bins per class** so that the dataset covers realistic conditions over the full dynamic range.

- **RF front-end impairments**
  - Implemented in `frontend/` and applied to **all** classes (including `NoJam`), so that “clean” data still looks like a real receiver:
    - DC offsets and IQ gain/phase mismatch.
    - CFO + phase noise.
    - BPF ripple, colored noise, spurs.
    - AGC and ADC quantization.
  - The entry points are:
    - `make_frontend_params.m` – random but bounded parameters.
    - `apply_frontend.m` – applies all effects to a given complex baseband sequence.

- **Stratified dataset builder**
  - Main script: **`signal_generation_jammertest.m`**.
  - Builds **TRAIN / VAL / TEST** splits with **exact per-class quotas**:
    - Classes: `NoJam`, `Chirp`, `NB`, `WB` (configurable).
    - Per-split / per-class sample counts set in a `Quota` structure.
  - For each IQ tile the script:
    1. Picks the dataset split and class.
    2. Draws a band (`L1CA`, `L2C`, `L5`, `E1OS`).
    3. Draws C/N0 and JSR from configurable bins (global defaults or per-class overrides).
    4. Draws jammer **family** parameters (for example, USB / cigarette / multiband handheld ranges).
    5. Runs `Fct_Channel_Gen` to synthesise GNSS + jammer + AWGN + front-end impairments.
    6. Saves the tile and associated metadata to disk.

  - Output:
    - Complex baseband tile: `GNSS_plus_Jammer_awgn` (column vector).
    - Metadata struct: `meta` (includes band, jammer type, C/N0, JSR, power statistics, front-end parameters).

---

## 2. Repository structure

At the top level:

```text
.
├── Channel/                 # Channel, C/N0, JSR and GNSS-like core generator
├── GNSS_signals/            # GNSS signal generation code derived from GNSS-matlab
├── Init/                    # High-level parameter initialization functions
├── Jammer_signals/          # Jammer waveforms and jammer factory
├── Utils/                   # Common helpers (PRN, filters, band maps, random walks, etc.)
├── frontend/                # RF front-end artifacts (CFO, phase noise, AGC/ADC, IQ imbalance...)
├── signal_generation_jammertest.m  # Main script to generate stratified datasets
└── .gitignore
```

Key components:

- **`Init/Fct_GNSS_parameters.m`**  
  Sets GNSS-related parameters (chip rate, sampling frequency, spreading factor, etc.).

- **`Init/Fct_Jammer_parameters.m`** and **`Init/fct_jammer_parameters_w.m`**  
  Default parameter ranges and presets for the jammer families.

- **`Init/Fct_Channel_parameters.m`** and **`Init/Fct_Sim_parameters.m`**  
  General simulation and channel parameters (tile length `Ns`, sample rate `Fs`, etc.).

- **`Channel/Fct_Channel_Gen.m`**  
  High-level entry point for **one tile**:
  - Builds GNSS-like baseline.
  - Adds AWGN with target C/N0 (dB-Hz).
  - Calls `jammer_factory` for jammer waveform, scales to target JSR.
  - Applies RF front-end chain.
  - Returns IQ tile and `meta` structure with detailed provenance.

- **`Jammer_signals/jammer_factory.m`**  
  Maps logical jammer class + family to specific low-level generators:
  - `jam_chirp`, `jam_nb_prn`, `jam_wb_prn`, `jam_cw`, `jam_fh`, `jam_none`.

- **`frontend/apply_frontend.m` & `frontend/make_frontend_params.m`**  
  Draw and apply front-end impairments.

---

## 3. Requirements

- **MATLAB** R2020b or newer is recommended (older versions may work, but have not been tested thoroughly).
- **Toolboxes**:
  - Signal Processing Toolbox (for `fir1`, `hamming`, etc.).
  - Base MATLAB functions only for the rest (all random draws and complex arithmetic are done manually).

The project is pure MATLAB: there are **no** external mex files, C++ bindings, or Python dependencies.

---

## 4. Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/macaburguera/GNSS_generator.git
   cd GNSS_generator
   ```

2. **Open MATLAB** and set the working directory to the repo root:

   ```matlab
   cd('path/to/GNSS_generator');
   ```

3. **Add subfolders to the path** (the main script already does this, but you can do it manually if you prefer):

   ```matlab
   addpath(genpath('Init'));
   addpath(genpath('Utils'));
   addpath(genpath('Jammer_signals'));
   addpath(genpath('Channel'));
   addpath(genpath('GNSS_signals'));
   addpath(genpath('frontend'));
   ```

4. Verify that MATLAB can see the main script:

   ```matlab
   which signal_generation_jammertest
   ```

---

## 5. Usage

### 5.1. Quick start

1. Open `signal_generation_jammertest.m` in the MATLAB editor.
2. Inspect the **“USER CONFIG”** section near the top and adapt as needed:

   - `OutRoot` – root directory for the generated dataset (default: `datasets_jammertest` inside the repo).
   - `Seed` – global random seed (for deterministic, reproducible datasets).
   - `Fs`, `Ns` – sampling frequency and tile length (by design, fixed to **60 MHz** and **2048 samples** to match the Jammertest spectrogram tiles).
   - `ParamGNSS.SV_Number` – number of GNSS channels to sum (defaults to 8).
   - `Bands` – list of band tokens (e.g. `{'L1CA','L2C','L5','E1OS'}`).
   - `Classes` – list of logical classes (`{'NoJam','Chirp','NB','WB'}`).
   - `CountsSpec` / `Quota` – stratified counts for each **split × class**.
   - `CNo_bins_default`, `JSR_bins_default` – global bin edges for C/N0 and JSR.
   - `CNo_bins_by_class`, `JSR_bins_by_class` – optional per-class overrides.
   - `ChirpFamilies` – parameter ranges for each chirp “family” (USB, cigarette S1, S2, multiband handheld H3.3, etc.).

3. Run the script:

   ```matlab
   signal_generation_jammertest
   ```

4. After completion, you should see a structure like:

   ```text
   datasets_jammertest/
   ├── TRAIN/
   │   ├── NoJam/
   │   │   ├── TRAIN_NoJam_000001.mat
   │   │   └── ...
   │   ├── Chirp/
   │   ├── NB/
   │   └── WB/
   ├── VAL/
   │   └── ...
   └── TEST/
       └── ...
   ```

   Each `.mat` file contains:

   - `GNSS_plus_Jammer_awgn` – complex column vector with the IQ samples.
   - `meta` – struct with fields such as:
     - `band` – band token (`'L1CA'`, `'L2C'`, `'L5'`, `'E1OS'`).
     - `jam_name` / `jam_code` – logical class label.
     - `CNo_dBHz` / `CNR_dBHz` – effective C/N0.
     - `JSR_dB` – jammer-to-signal ratio.
     - `pow` – measured powers for GNSS, jammer, noise and output.
     - Front-end parameter struct (CFO, IQ imbalance, etc.).
     - Simulation settings: `fs_Hz`, `N`, `dt_s`, etc.

### 5.2. Integrating with ML pipelines

Typical downstream steps:

1. Load `.mat` tiles and extract IQ vectors.
2. Compute spectrograms / STFT / PSD or other features.
3. Train a classifier to discriminate `NoJam`, `Chirp`, `NB`, `WB` (possibly extended to more granular families).

This generator is intentionally separated from any ML framework, so you can plug it into Python, MATLAB, or any other environment.

---

## 6. License & attribution

- The project started from, and still contains, substantial code from  
  **GNSS-matlab** by **Dani Pascual**: <https://github.com/danipascual/GNSS-matlab>.  
  Please refer to that repository for the original license terms applying to the reused components.
- Any additional code and extensions in this repository are licensed under the terms specified in this repository’s own `LICENSE` file (to be added if not already present).

If you use this generator in your research, please acknowledge both the GNSS-matlab project and the Jammertest 2023 organisers whose RF descriptions inspired the jammer models.
