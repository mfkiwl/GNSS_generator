# GNSS_generator – Simulation Pipeline

This document gives a high-level view of how the **GNSS_generator** project is structured internally:
how parameters are initialised, how a single IQ tile is created, and how full TRAIN/VAL/TEST
datasets are produced.

It is meant as a “map of the code” that you can read together with the source files.

---

## 1. Top‑level flow

At the highest level, one run of `signal_generation_jammertest.m` does this:

1. Initialise global simulation, GNSS and jammer parameter structures.
2. For each **dataset split** (TRAIN / VAL / TEST) and each **class** (NoJam / Chirp / NB / WB):
   - Loop until the requested quota of tiles is met.
   - Draw random configuration (band, C/N0 bin, JSR bin, jammer family, etc.).
   - Call `Fct_Channel_Gen` to generate one IQ tile and metadata.
   - Save the result to disk as a `.mat` file.
3. Repeat until all splits and classes are filled.

Graphically:

```text
User config (CountsSpec, bands, classes, bins, seeds)
          ↓
 Init/*  → Fct_*_parameters.m
          ↓
 signal_generation_jammertest.m
          ↓
  [loop over split, class, sample]
          ↓
      Fct_Channel_Gen.m
          ↓
    GNSS_signals  +  Jammer_signals
          ↓
        Channel/  (C/N0, JSR, noise)
          ↓
        frontend/ (RF impairments)
          ↓
 GNSS_plus_Jammer_awgn  +  meta
          ↓
     write .mat files per split/class
```

---

## 2. Initialisation layer (`Init/`)

The `Init` folder contains small functions that assemble parameter structures. They are called
from `signal_generation_jammertest.m` early in the execution.

Main files:

- **`Fct_Sim_parameters.m`**
  - Global simulation settings:
    - `Fs` – sampling frequency (typically $60 \,\text{MHz}$).
    - `Ns` – samples per tile (e.g. $2048$).
    - Derived values such as `dt`, total duration per tile, etc.
  - Flags for plotting / debugging.

- **`Fct_GNSS_parameters.m`**
  - GNSS‑related settings:
    - Number of satellites / channels (`SV_Number`).
    - Chip rates, Doppler ranges, PRN selection.
    - Nominal C/N0 ranges (used as defaults if no per‑class override is given).

- **`Fct_Jammer_parameters.m`** and **`fct_jammer_parameters_w.m`**
  - Default parameter ranges for each jammer **family**:
    - Centre frequencies per band.
    - Jamming bandwidths.
    - Sweep periods for chirps.
    - Which bands are active for multiband devices (L1/L2/L5/E1 combinations).
  - These are later specialised by `signal_generation_jammertest.m` when defining families
    corresponding to specific Jammertest devices.

- **`Fct_Channel_parameters.m`**
  - Channel model options:
    - C/N0 computation mode.
    - Noise power normalisation conventions.
    - Optional fading flags (currently kept simple).

Each of these returns a struct; the main script keeps them in variables like
`ParamSim`, `ParamGNSS`, `ParamJam`, `ParamChannel`.

---

## 3. Tile generation core (`Channel/Fct_Channel_Gen.m`)

The **core generator** for *one* IQ tile is `Channel/Fct_Channel_Gen.m`.

Given:
- simulation parameters (`ParamSim`),
- GNSS parameters (`ParamGNSS`),
- jammer configuration (`JamCfg`),
- channel parameters (`ParamChannel`),
- frontend configuration (`FE`),

it performs:

1. **GNSS baseband synthesis**
   - Uses functions derived from `GNSS-matlab` inside `GNSS_signals/` to create several PRN‑like
     channels.
   - Sums them into a complex baseband signal `s_gnss[n]` with power normalised according to
     the requested C/N0.

2. **Jammer synthesis**
   - Calls `Jammer_signals/jammer_factory.m` with a logical class (NoJam / Chirp / NB / WB)
     and a **family** (USB, CigS1, H3_3, …).
   - The factory:
     - Selects the correct low‑level waveform generator (`jam_chirp`, `jam_nb_prn`, `jam_wb_prn`,
       `jam_cw`, `jam_fh`, or `jam_none`).
     - Configures its parameters (bandwidth, sweep period, active bands, etc.).
   - Produces a baseband jammer signal `s_jam[n]` at the same sampling rate `Fs`.

3. **C/N0 and JSR enforcement (Channel)**
   - Noise:
     - Computes the necessary noise variance to achieve the target **C/N0** in dB‑Hz for the GNSS
       component, given `Fs` and the number of samples.
     - Generates complex AWGN `w[n]` with that variance.
   - JSR:
     - Measures the in‑band power of `s_gnss` and `s_jam` over the tile.
     - Scales `s_jam` so that the resulting jammer‑to‑signal ratio matches the desired **JSR_dB**.
   - Forms the “ideal” channel output:
     - `s_ch[n] = s_gnss[n] + s_jam[n] + w[n]`.

4. **RF front‑end impairments**
   - Calls `frontend/apply_frontend.m` with:
     - baseband input `s_ch[n]`,
     - frontend parameters `FE` drawn previously by `make_frontend_params.m`.
   - Applies (with randomised but bounded strengths):
     - Carrier frequency offset and phase noise.
     - IQ gain and phase imbalance.
     - DC offsets.
     - Mild BPF colouration / spurs.
     - Quantisation (if enabled).
   - Returns the final complex baseband sequence:
     - `z[n] = GNSS_plus_Jammer_awgn`.

5. **Metadata**
   - Assembles a `meta` struct with fields grouped as:
     - Simulation information (`fs_Hz`, `N`, `dt_s`, time stamps, split, class, family).
     - GNSS parameters (number of SVs, nominal C/N0, band token).
     - Jammer parameters (class, family, bandwidth, sweep period, active bands).
     - Channel statistics (measured powers, effective C/N0 and JSR after scaling).
     - Frontend parameters (CFO, IQ imbalance, DC, noise colours).

`Fct_Channel_Gen` is the *only* function that knows about all layers; everything else
is either configuration or a sub‑module.

---

## 4. Dataset builder (`signal_generation_jammertest.m`)

`signal_generation_jammertest.m` orchestrates many calls to `Fct_Channel_Gen` to build
full datasets.

### 4.1. Split and class configuration

The script defines:

- **Splits**: `TRAIN`, `VAL`, `TEST`.
- **Classes**: typically `NoJam`, `Chirp`, `NB`, `WB`.
- **Quotas**:
  - A structure such as `CountsSpec(split).(class)` or `Quota(split, class)` specifies
    the exact number of tiles required for each combination.
  - From this, the script builds a list of `(split, class)` targets.

### 4.2. Random configuration per tile

For each `(split, class)` and while the quota is not yet met, the script:

1. Draws a **band** token from a predefined list (`L1CA`, `L2C`, `L5`, `E1OS`).
2. Draws a **C/N0 bin** and a **JSR bin**:
   - Uses global defaults (`CNo_bins_default`, `JSR_bins_default`) or
     per‑class overrides if they exist.
   - Within each bin a uniform random value is selected.
3. Chooses a **jammer family** compatible with the class:
   - For example, for `Chirp` it may select among USB, CigS1, CigS2, H3_3, etc.
   - Each family has its own parameter ranges (bandwidth, sweep period, multiband layout).
4. Constructs a `JamCfg` struct encapsulating all of this and passes it to `Fct_Channel_Gen`.
5. Receives `GNSS_plus_Jammer_awgn` and `meta`, and writes them to:
   - `[OutRoot]/[SPLIT]/[CLASS]/[SPLIT]_[CLASS]_[NNNNNN].mat`.

### 4.3. Reproducibility

- A **global seed** is set at the top of the script.
- All random decisions (bands, bins, families, frontend parameters) ultimately come from MATLAB’s RNG.
- As long as:
  - the seed,
  - quotas,
  - and the ordering logic
  stay unchanged, regenerating the dataset yields identical tiles.

---

## 5. Modules overview

To quickly locate functionality:

- **GNSS signals**
  - Folder: `GNSS_signals/`
  - Provides PRN generation, code/carrier mixing, Doppler handling.
  - Derived from Dani Pascual’s **GNSS‑matlab** project.

- **Jammer signals**
  - Folder: `Jammer_signals/`
  - Low‑level waveforms:
    - `jam_chirp`, `jam_nb_prn`, `jam_wb_prn`, `jam_cw`, `jam_fh`, `jam_none`.
  - High‑level dispatcher:
    - `jammer_factory` selects the generator and parameters based on class + family.

- **Channel**
  - Folder: `Channel/`
  - Entry point: `Fct_Channel_Gen`.
  - Helper functions for noise power, C/N0 computation, JSR scaling.

- **Frontend**
  - Folder: `frontend/`
  - `make_frontend_params` draws a parameter struct.
  - `apply_frontend` applies RF artefacts.

- **Utils**
  - Folder: `Utils/`
  - Shared helpers: band maps, power estimators, random walks, filter design, etc.

---

## 6. How this ties into downstream projects

The output of this generator is intentionally simple:

- One complex vector `GNSS_plus_Jammer_awgn` per tile.
- One metadata struct `meta`.

This makes it easy to:

- Load the tiles in Python (via `scipy.io.loadmat`) or MATLAB.
- Compute PSDs, spectrograms, and higher‑level features.
- Train detectors / classifiers / regressors for:
  - jamming presence,
  - jamming class,
  - estimation of C/N0, JSR or device family.

The `meta` struct acts as the “ground truth contract” between this generator and your
machine‑learning repositories.
