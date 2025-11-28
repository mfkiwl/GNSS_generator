function ParamJam = Fct_Jammer_parameters(Fs)
% Fct_Jammer_parameters
% Canonical jammer parameters for the Jammertest-style generator.
% This version keeps ONLY four dataset classes:
%   - NoJam
%   - Chirp  (all sweep / chirp devices)
%   - NB     (narrowband PRN-like)
%   - WB     (wideband PRN-like)
%
% It also provides a few helper ranges used by the new generator.

if nargin < 1 || isempty(Fs)
    Fs = 60e6;  % default Jammertest sampling rate
end

ParamJam = struct();
ParamJam.Fs = Fs;

% =====================================================================
% 1) Canonical dataset classes (no CW, no FH anymore)
% =====================================================================
ParamJam.class_set = {'NoJam','Chirp','NB','WB'};

% Optional: which RF bands the generator can use (not critical, but handy)
ParamJam.allowed_bands = {'L1','L2','L5','E1','E5a','G1'};

% =====================================================================
% 2) Legacy-style parameter ranges (used by old code, still harmless)
% =====================================================================

% ---- Chirp / Sweep ---------------------------------------------------
% These are generic ranges; the *actual* families (U1.x, S1.x, S2.x,
% H1.1, H3.3, H4.1, ...) are set in build_jammer_params.m.
ParamJam.chirp.period_us = [5, 60];   % sweep period (covers 5–60 µs)
ParamJam.chirp.bw_MHz    = [20, 100]; % sweep BW (covers 20–100 MHz devices)
ParamJam.chirp.wave      = 'sawtooth';
ParamJam.chirp.edge_win  = 0.02;      % taper on/off edges (fraction of tile)

% ---- NB PRN (~1 MHz) -------------------------------------------------
ParamJam.nb.chip_rate_Hz  = [0.8e6, 1.2e6];
ParamJam.nb.rolloff       = 0.35;
ParamJam.nb.osc_offset_Hz = [8.7e6, 9.3e6];  % we later multiply by ±1

% ---- WB PRN (~10 MHz) ------------------------------------------------
ParamJam.wb.chip_rate_Hz  = [8e6, 12e6];
ParamJam.wb.rolloff       = 0.25;
ParamJam.wb.osc_offset_Hz = [-5e6, +5e6];

% =====================================================================
% 3) Dataset prior (class probabilities)
% =====================================================================
% order:  NoJam  Chirp   NB     WB
% (normalized version of your original prior without CW/FH)
ParamJam.target_classes_prob = [0.294, 0.412, 0.118, 0.176];

% One-band-per-sample policy (kept as in your original design)
ParamJam.per_sample_bands = 'random_one';

% =====================================================================
% 4) Helpers (used by the updated generator, harmless elsewhere)
% =====================================================================
helpers = struct();

% Jammertest-like C/N0 and JSR ranges (not used directly in the
% main script, but kept for completeness)
helpers.CNR_dBHz_rng = [30 70];  % realistic GNSS C/N0
helpers.JSR_dB_rng   = [0 60];   % jammer-to-signal ratio (in-band)

% Bursting: duty randomly in [0.35..1]; gate length ~ sample length
helpers.burst = @() struct( ...
    'duty', 0.35 + 0.65*rand(), ...
    'len',  [] ...
);

% Slow frequency wander model parameters (for CW/NB etc in older code)
helpers.wander = @() struct( ...
    'sigma',   2 + 18*rand(), ...
    'fcorner', 10 + 60*rand() ...
);

ParamJam.helpers = helpers;
end
