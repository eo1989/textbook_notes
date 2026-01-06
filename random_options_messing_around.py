# %%

from decimal import DivisionByZero
from typing import Any
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import norm
import seaborn as sns

sns.set_style('ticks')
sns.set_context('notebook', rc = {'lines.linewidth': 0.6})
plt.figure(figsize = (8, 6))

# %%
def N(x: float|np.ndarray) -> float|np.ndarray:
    """ Normal distribution function """
    return norm.cdf(x)

# def S(self, S: float) -> float|DivisionByZero:
# 	if S >= 0:
# 		return S
# 	elif S <= 0:
# 		return DivisionByZero("S must be greater than 0")
# def S(self, S: float) -> Any:
# 	self.S = S
# 	return S if S >= 0 else DivisionByZero("S must be greater than 0")

def K(self, K: float) -> Any:
    self.K = K
    return K if K >= 0 else exit

def opt(S: float, K: float, r: float, sigma: float, ttm: float, c_or_p: str) -> float:
    """
    Euro call/put price calc, again, using BSM & python types
    S: spot
    K: strike
    r: risk free rate
    sigma: volatility
    ttm: time to maturity
    c_or_p: call or put
    """
    d1 = (np.log(S/K) + (r + 0.5*(sigma**2)) * ttm) / (sigma * np.sqrt(sigma))
    d2 = d1 - sigma * np.sqrt(ttm)

    if (c_or_p == "call"):
        return (S*N(d1) - K*np.exp(-r * ttm)*N(d2))
    else:
        return (K*np.exp(-r*ttm) * N(-d2) - S*N(-d1))

# %%
from IPython.display import display, Latex, display_latex
from IPython.display import display, Markdown, display_markdown

display(Latex("""
$$
Option price w/ respect to underlying:
\delta = \frac{\partial V}{\partial S}
\gamma = \frac{\partial^2 V}{\partial S^2}

\frac{\delta p}{\delta S} = \frac{delta c}$${\delta S}
$$
"""))

# display_latex("""
# Option price w/ respect to underlying:
# \delta = \frac{\partial V}{\partial S}
# \gamma = \frac{\partial^2 V}{\partial S^2}

# \frac{\delta p}{\delta S} = \frac{delta c}{\delta S}
# """, raw = True)

s = [i for i in range(0, 101)]
c = [opt(S = i, K = 50, r = 0.04, sigma = 0.3, ttm = 1, c_or_p="call") for i in range(0, 101)]
p = [opt(S = i, K = 50, r = 0.04, sigma = 0.3, ttm = 1, c_or_p="put") for i in range(0, 101)]

df = pd.DataFrame(data = {'Underlying': s, 'Call':c, 'Put': p})
sns.lineplot(data = df)
plt.axvline(x = 50, ls = '-.', c = 'black')

# %%
sns.lineplot(data = df, x = 'Underlying', y = 'Call', color = 'green')
plt.axvline(x = 50, ls = '-', c = 'black')
# %%
sns.lineplot(data = df, x = 'Underlying', y = 'Put', color = 'red')
plt.axvline(x = 50, ls = '-', c = 'black')
#%%
"""
Option Price w.r.t. strike:
# TODO redo this as long calls go higher with increase in underlying.
"""
# s = [i for i in range(1, 101)]
# k = [i for i in range(1, 101)]
# c = [opt(S = 50, K = i, r = 0.05, sigma = 0.3, ttm = 1, c_or_p = "call") for i in range(1, 101)]
# p = [opt(S = 50, K = i, r = 0.05, sigma = 0.3, ttm = 1, c_or_p = "put") for i in range(1, 101)]

# df = pd.DataFrame(data = {'Underlying': s, 'Strike': k, 'Call': c, 'Put': p})
# %%
# sns.lineplot(data = df, x = 'Strike', y = 'Call', color = 'green')
# plt.axvline(x = 50, ls = '-', c = 'black')
# %%
# sns.lineplot(data = df, x = 'Strike', y = 'Put', color = 'red')
# plt.axvline(x = 50, ls = '-', c = 'black')
# %%
"""
Options w.r.t time to maturity
"""
t = np.linspace(start = 0, stop = 5, num = 100)
c = [opt(S = 50, K = 50, r = 0.05, sigma = 0.30, ttm = t[i], c_or_p="call") for i in range(0, len(t))]
p = [opt(S = 50, K = 50, r = 0.05, sigma = 0.30, ttm = t[i], c_or_p="put") for i in range(0, len(t))]

fig, axes = plt.subplots(2, 1)

df = pd.DataFrame(data = {'T': t, 'Call': c, 'Put': p})
sns.lineplot(data = df, x = 'T', y = 'Call', color = 'green', ax = axes[1])
sns.lineplot(data = df, x = 'T', y = 'Put', color = 'red', ax = axes[0])


# %%

"""
Options w.r.t to vol
"""
vol = np.linspace(start = 0, stop = 1.5, num = 100)
c = [opt(S = 50, K = 50, r = 0.05, sigma = vol[i], ttm = 1, c_or_p="call") for i in range(0, len(vol))]
p = [opt(S = 50, K = 50, r = 0.05, sigma = vol[i], ttm = 1, c_or_p="put") for i in range(0, len(vol))]

fig, axes = plt.subplots(2, 1)

df = pd.DataFrame(data = {'Vol': vol, 'Call': c, 'Put': p})
sns.lineplot(data = df, x = 'Vol', y = 'Call', color = 'g', ax = axes[1])
sns.lineplot(data = df, x = 'Vol', y = 'Put', color = 'r', ax = axes[0])

# %%
"""
Options w.r.t to the risk-free rate
"""
rate = np.linspace(0, 0.2, num = 100)
c = [opt(S = 50, K = 50, r = rate[i], sigma = 0.3, ttm = 1, c_or_p="call") for i in range(0, 100)]
p = [opt(S = 50, K = 50, r = rate[i], sigma = 0.3, ttm = 1, c_or_p="put") for i in range(0, 100)]

fig, axes = plt.subplots(2, 1)

df = pd.DataFrame(data = {'Risk-free Rate': rate, 'Call': c, 'Put': p})
sns.lineplot(data = df, x = 'Risk-free Rate', y = 'Call', color = 'g',
             ax = axes[1]   )
sns.lineplot(data = df, x = 'Risk-free Rate', y = 'Put', color = 'r', ax = axes[0])
# %%
