import jax.numpy as jnp
import numpyro
from numpyro import distributions as dist
from numpyro.contrib.control_flow import scan

## Error Models ##

def homoscedastic() -> None:

    # Fixed hyperparameters
    c_0 = 2.5
    g_0 = 5
    G_0 = 3.33
    C_0 = numpyro.sample('C_0', dist.Gamma(g_0, G_0))
    sigma2 = numpyro.sample('sigma2', dist.InverseGamma(c_0, C_0))
    return sigma2


def stochastic_volatility(n_timesteps):
    """
    Implements a stochastic volatility model for observation error in NumPyro. This follows the AR1 model and associated hyperparameters presented in:
        Knaus, P., Bitto-Nemling, A., Cadonna, A., & Fruhwirth-Schnatter, S. (2021). Shrinkage in the Time-Varying Parameter Model Framework Using the R Package shrinkTVP.
        Journal of Statistical Software, 100(13).
        https://doi.org/10.18637/jss.v100.i13

        We estimate the log-volatility (h_t) from which is derived the heteroscedastic (sigma_t).

        Use this by just importing and calling from your NumPyro model to obtain sigma2.

    Parameters
    ----------
    tcarry : [TODO:parameter]
        
    _ : [TODO:parameter]
        [TODO:description]

    Returns
    -------
    [TODO:return]
        [TODO:description]

    """

    # Fixed hyperparameters
    b_mu = 0.0
    a_phi = 5.0
    b_phi = 1.5
    B_mu = 1.0
    B_sigma = 1.0
    
    sv_phi = numpyro.sample('sv_phi', dist.Beta(a_phi, b_phi))
    sv_phi_trans = (sv_phi*2) - 1
    sv_sigma2_eta = numpyro.sample('sv_sigma2_eta', dist.Gamma(0.5, 0.5 * B_sigma))
    sv_mu = numpyro.sample('sv_mu', dist.Normal(b_mu, jnp.sqrt(B_mu)))
    h_0 = numpyro.sample('h_0', dist.Normal(sv_mu, jnp.sqrt(sv_sigma2_eta / (1 - sv_phi_trans**2))))
    scan_vars = (h_0, )


    def sv_ht_scan(tcarry, _):
        # sample h_t given h_t - 1, params
        (h_curr, ) = tcarry
        h_curr = numpyro.sample('h_t', dist.Normal(
            sv_mu + sv_phi_trans * (h_curr - sv_mu),
            jnp.sqrt(sv_sigma2_eta)
        ))
        tcarry = (h_curr, )
        return tcarry, h_curr

    _, h_t = scan(sv_ht_scan, scan_vars, jnp.zeros(n_timesteps))

    sigma2 = numpyro.deterministic('sigma2', jnp.exp(h_t))
    return sigma2



