# GNSS_generator – Jammer Models

This document describes how the **jammer models** in `Jammer_signals/` are organised and how they
relate to the logical classes (`NoJam`, `Chirp`, `NB`, `WB`) and to Jammertest‑style equipment.

The goal is to make explicit the assumptions baked into the generator so that experiments can be
reproduced and extended safely.

---

## 1. Logical classes vs. waveform types

The generator uses four **logical classes** for machine learning:

- `NoJam` – GNSS + noise only (no jammer).
- `Chirp` – swept / chirp‑like interference, often broadband.
- `NB` – narrowband jamming (single or few tones / narrow PRN).
- `WB` – wideband PRN‑like jamming.

These are mapped internally to **waveform types** implemented in `Jammer_signals/`:

| Waveform function | Description                                    | Typical class |
|-------------------|------------------------------------------------|---------------|
| `jam_none`        | Zero signal (no jammer)                        | `NoJam`       |
| `jam_chirp`       | Frequency‑swept (linear) noise‑like chirp      | `Chirp`       |
| `jam_nb_prn`      | PRN‑like narrowband signal                     | `NB`          |
| `jam_wb_prn`      | PRN‑like wideband signal                       | `WB` / `Chirp` (depending on config) |
| `jam_cw`          | Single continuous‑wave tone                    | `NB`          |
| `jam_fh`          | Simple frequency‑hopping pattern               | `Chirp` / `NB` |

The mapping from **class** + **family name** to a specific waveform function and parameter set
is handled by `jammer_factory.m`.

---

## 2. Jammer families

A *family* is a configuration template corresponding to a Jammertest‑style device or group of
devices (for example “USB car charger” or “handheld multiband jammer”).

Each family has:

- A **logical class** (`Chirp`, `NB`, `WB`).
- One or more **active bands** (L1, L2, L5, E1).
- A **waveform type** (`jam_chirp`, `jam_nb_prn`, …).
- Parameter ranges (bandwidth, sweep period, hopping rate, etc.).

The exact family list is defined in `signal_generation_jammertest.m`, but the typical structure is:

| Family name | Logical class | Waveform | Bands                         | Notes |
|-------------|---------------|----------|-------------------------------|-------|
| `USB`       | `Chirp`       | `jam_chirp` | L1 only                        | Car‑charger / USB‑style chirp, mid BW, moderate power. |
| `CigS1`     | `Chirp`       | `jam_chirp` | L1 only                        | Cigarette‑lighter jammer, relatively narrow BW. |
| `CigS2`     | `Chirp`       | `jam_chirp` | L1 only                        | Variant with slightly different BW / sweep period. |
| `H3_3`      | `Chirp`       | `jam_chirp` | L1 + L2 + L5 (multiband)      | Handheld multiband jammer, fairly wide sweep, more power. |
| `NB_L1`     | `NB`          | `jam_nb_prn` / `jam_cw` | L1 only           | Narrow PRN or CW tone jamming around L1. |
| `NB_L2`     | `NB`          | `jam_nb_prn` / `jam_cw` | L2 only           | Equivalent but centred on L2. |
| `WB_L1`     | `WB`          | `jam_wb_prn`            | L1 only           | Wideband PRN, strong interference over L1. |
| `WB_L1L2`   | `WB`          | `jam_wb_prn`            | L1 + L2           | Wideband across multiple GNSS bands. |

> **Note**  
> The exact set of families and their parameter ranges is chosen to approximate
> the qualitative behaviour of devices described in the Jammertest documentation,
> not to model specific hardware at datasheet level.

When the dataset is generated, `signal_generation_jammertest.m` chooses:

- A **logical class** (e.g. `Chirp`),
- Then, randomly, a **family** among those compatible with that class (e.g. `USB`, `CigS1`, `CigS2`, `H3_3`),
- And finally draws specific parameters within that family’s ranges.

---

## 3. Parameter ranges

Below is the conceptual structure of the parameters; actual numeric ranges live in
`Init/Fct_Jammer_parameters.m`, `Init/fct_jammer_parameters_w.m` and in the family definitions
inside `signal_generation_jammertest.m`.

### 3.1. Chirp jammers (`jam_chirp`)

Parameters:

- `BW_Hz` – sweep bandwidth (per band).
- `T_chirp` – sweep period.
- `centre_freq` – centre of the sweep within each band.
- `multiband_mask` – which of {L1, L2, L5, E1} are active.

Families typically differ in:

- Bandwidth:
  - USB / Cigarette: tens of MHz around L1.
  - Handheld multiband: wider, possibly spanning each entire GNSS band.
- Sweep period:
  - Ranging from a few microseconds (fast sweep) to milliseconds (slower sweep).
- Number of active bands:
  - Single‑band devices (L1 only).
  - Multiband devices (L1+L2, or L1+L2+L5).

### 3.2. Narrowband jammers (`jam_nb_prn`, `jam_cw`)

Parameters:

- `f_offset` – offset from the GNSS carrier centre (Hz).
- `BW_Hz` – small occupied bandwidth (for PRN).
- `is_tone` – whether it degenerates into a pure tone.

Families:

- `NB_L1`, `NB_L2`, `NB_L5`, etc.
- Each family restricts:
  - band centre (L1, L2…),
  - maximum offset,
  - maximum bandwidth.

These are typically used when creating the `NB` class, but can also be mixed as “light”
interference in other classes if desired.

### 3.3. Wideband PRN jammers (`jam_wb_prn`)

Parameters:

- `BW_Hz` – large occupied bandwidth (covering a big fraction of the GNSS band).
- `chip_rate` – PRN chipping rate (often higher than GNSS C/A).
- `band_mask` – bands where wideband jamming is active.

Families:

- `WB_L1` – only L1 affected.
- `WB_L1L2` – L1 and L2 affected simultaneously.

These are used to populate the `WB` class in ML datasets.

### 3.4. Frequency‑hopping jammers (`jam_fh`)

Parameters:

- `hop_rate` – how often the tone jumps (Hz).
- `hop_band` – total span over which frequencies are chosen.
- `tone_BW` – narrowband width around each hop frequency.

Families:

- Experimental or used for specific tests where a hopping‑like pattern is needed.
- Typically mapped to `Chirp` or `NB` classes depending on the effective occupancy.

---

## 4. How `jammer_factory` works

`Jammer_signals/jammer_factory.m` is the single entry point that other code calls.

Inputs (conceptually):

- `class_name` – `'NoJam'`, `'Chirp'`, `'NB'`, `'WB'`.
- `family_name` – e.g. `'USB'`, `'CigS1'`, `'H3_3'`, `'NB_L1'`.
- Band token – `'L1CA'`, `'L2C'`, `'L5'`, `'E1OS'`.
- Tile length `N` and sampling rate `Fs`.
- Parameter structures from the `Init` layer.

Steps:

1. Look up the **family definition**:
   - Associated waveform type.
   - Parameter ranges.
   - Active bands.

2. Instantiate **low‑level parameters**:
   - Draw `BW_Hz`, `T_chirp`, `f_offset`, etc., uniformly or log‑uniformly inside the specified ranges.
   - Convert band tokens into baseband‑equivalent frequencies.

3. Call the corresponding waveform generator:
   - `jam_chirp(Fs, N, params)`
   - `jam_nb_prn(Fs, N, params)`
   - `jam_wb_prn(Fs, N, params)`
   - `jam_cw(Fs, N, params)`
   - `jam_fh(Fs, N, params)`
   - or `jam_none(Fs, N)`.

4. Return:
   - Jammer signal `s_jam[n]`.
   - A struct `jam_meta` that is later merged into the global `meta` for the tile.

This indirection makes it easy to:

- Add or remove families without touching the channel or frontend code.
- Swap waveform generators while keeping ML labels and family names stable.

---

## 5. Extending the jammer set

To add a new jammer “type” while keeping datasets compatible:

1. **Decide the logical class**
   - Does it behave more like `Chirp`, `NB`, or `WB`?
   - Or should you introduce a new class (e.g. `CW`) and update the ML pipelines?

2. **Add a family definition**
   - Choose a new `family_name` string.
   - Specify:
     - `class_name`,
     - bands,
     - waveform type (`jam_*`),
     - parameter ranges (BW, sweep period, offsets, etc.).

3. **Update `jammer_factory`**
   - Map `(class_name, family_name)` to the chosen waveform and ranges.

4. **Update dataset script**
   - Insert the new family in the list of families for that class.
   - Optionally give it its own C/N0 / JSR bins.

5. **Regenerate datasets**
   - Re‑run `signal_generation_jammertest.m` to produce new tiles including the new family.

By keeping this document in sync with the definitions in code, you ensure that anyone using the
datasets understands what “Chirp USB” or “NB_L1” actually mean in signal‑processing terms.
