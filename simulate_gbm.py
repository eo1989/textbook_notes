# From Python for Finance (2E, 2022)
# %%
import numpy as np
import pandas as pd
import yfinance as yf

def simulate_gbm(S_0, mu, sigma, N_SIMS, T, N, random_seed = 42, antithetic_var = False):
    np.random.seed(random_seed)

    dt = T/N  # time increment

    if antithetic_var:
        dW_ant = np.random.normal(scale = np.sqrt(dt), size = (int(N_SIMS/2), N + 1))
        dW = np.concatenate((dW_ant, -dW_ant), axis = 0)
    else:
        dW = np.random.normal(scale = np.sqrt(dt), size = (N_SIMS, N + 1))

    S_t = S_0 * np.exp(np.cumsum((mu - 0.5 * sigma**2)*dt + sigma * dW, axis = 1))
    S_t[:, 0] = S_0
    return S_t


# %%
## Test the simulation
df = yf.download("AAPL", start = "2022-01-01", end = "2023-01-31", auto_adjust=True)
