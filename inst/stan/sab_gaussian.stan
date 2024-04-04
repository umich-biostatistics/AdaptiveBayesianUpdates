// Sensible Adaptive Bayes, continuous outcomes
// To implement the original version in Boonstra and Barbaro (2018),
// beta^o+P*beta^a ~ N(alpha_prior_mean_stan, eta * alpha_prior_cov_stan)
// - set omega_mean_stan = 0, omega_sd_stan = 0
// To implement version 2 in Boonstra and Orozco del Pino,
// beta^o+P*beta^a ~ N(omega * alpha_prior_mean_stan, omega^2 * alpha_prior_cov_stan)
// - set eta_param_stan = Inf and omega_sq_in_variance = 1 if you want omega^2 to scale the variance
// - set eta_param_stan < Inf and omega_sq_in_variance = 0 if you want omega to only scale the mean
// This is all controlled in glm_sab and glm_sab2
data {
  int<lower = 1> n_stan; // n_curr
  int<lower = 1> p_stan; // number of original covariates
  int<lower = 0> q_stan; // number of augmented (or added) covariates
  real y_stan[n_stan]; // outcome
  matrix[n_stan, p_stan + q_stan] x_standardized_stan; // covariates (no intercept)
  matrix[p_stan, q_stan] aug_projection_stan; // {v^o}^(-1) %*% (E[V^a|v^o]- E[V^a|v^o = 0]), Eqn (9)
  vector[p_stan] alpha_prior_mean_stan; // m_alpha
  matrix[p_stan, p_stan] alpha_prior_cov_stan; // S_alpha
  vector[p_stan] sqrt_eigenval_hist_var_stan; // sqrt of eigenvalues of S_alpha; D^1/2 in Equation (S6)
  matrix[p_stan, p_stan] eigenvec_hist_var_stan; // eigenvectors of S_alpha; Q^T in Equation (S6)
  real<lower = 0> local_dof_stan; // dof of pi(lambda), = 1
  real<lower = 0> global_dof_stan; // dof of pi(tau), = 1
  real<lower = 0> beta_orig_scale_stan; // c, Section 2
  real<lower = 0> beta_aug_scale_stan; // c, Section 2
  // d in Section 2 is InvGamma(slab_dof_stan/2,slab_scale_stan^2*slab_dof_stan/2)
  real<lower = 0> slab_dof_stan; //
  real<lower = 0> slab_scale_stan;
  vector<lower = 0>[p_stan] scale_to_variance225; //Equation (S6); equal to diag(S_alpha) / 225;
  int<lower = 0, upper = 1> phi_prior_type; //if 1, phi is apriori truncated normal; if 0, phi is apriori beta
  real<lower = 0, upper = 1> phi_mean_stan; //
  real<lower = 0> phi_sd_stan; //
  real<lower = 0> eta_param_stan; // eta ~ IG(eta_param_stan, eta_param_stan)
  real omega_mean_stan; //
  real<lower = 0> omega_sd_stan; //
  real<lower = 0> mu_sd_stan; // prior standard deviation on intercept
  int<lower = 0, upper = 1> only_prior;//if 1, ignore the model and data and generate from the prior only
  int<lower = 0, upper = 1> omega_sq_in_variance; // if 1, then omega^2 will scale the variance of the sab prior. Otherwise it won't
}
transformed data {
  vector[p_stan] zero_vec;
  real phi_beta_shape1;
  real phi_beta_shape2;
  real phi_mean_stan_trunc;
  real phi_sd_stan_trunc;
  zero_vec = rep_vector(0.0, p_stan);
  // These next four lines will only be used if phi is beta distributed
  // Depending on the values of phi_mean_stan or phi_sd_stan, the resulting
  // shape parameters could give stan fits
  phi_mean_stan_trunc = fmax(1e-6, fmin(1 - 1e-6, phi_mean_stan));
  phi_sd_stan_trunc = fmax(1e-6, fmin(sqrt(phi_mean_stan_trunc * (1 - phi_mean_stan_trunc)) - 1e-6, phi_sd_stan));
  phi_beta_shape1 = phi_mean_stan_trunc * (phi_mean_stan_trunc * (1 - phi_mean_stan_trunc) / phi_sd_stan_trunc^2 - 1);
  phi_beta_shape2 = (1 - phi_mean_stan_trunc) * (phi_mean_stan_trunc * (1 - phi_mean_stan_trunc) / phi_sd_stan_trunc^2 - 1);
}
parameters {
  real mu;
  vector[p_stan] beta_raw_orig; // unscaled
  vector[q_stan] beta_raw_aug; // unscaled
  real<lower = 0> tau_glob; // tau
  vector<lower = 0>[p_stan] lambda_orig;// lambda^o
  vector<lower = 0>[q_stan] lambda_aug; // lambda^a
  real<lower = 0> slab; // d^2, Section 2
  real<lower = 0, upper = 1> phi;// phi
  real<lower = 0> eta;
  real<lower = 0> omega;
  real<lower = 0> sigma;
}
transformed parameters {
  vector[p_stan] normalized_beta; //entire LHS of Equation (S6)
  vector[p_stan] beta_orig; // scaled
  vector[q_stan] beta_aug; // scaled
  vector[p_stan + q_stan] beta;
  vector<lower = 0>[p_stan] theta_orig;// theta
  vector<lower = 0>[q_stan] theta_aug;// theta
  vector<lower = 0>[p_stan] hist_orig_scale;//Diagonal of Gamma^{-1} in LHS of Eqn (S6)
  matrix[p_stan,p_stan] normalizing_cov;// S_alpha * hist_orig_scale  + Theta^o
  real<lower = 0, upper = 1> phi_copy;// to gracefully allow for zero-valued prior standard deviation
  real<lower = 0> eta_copy;// to gracefully allow for point mass on 1
  real<lower = 0> omega_copy;// to gracefully allow for zero-valued prior standard deviation
  real<lower = 0> slab_copy;// to gracefully allow for infinite slab_dof_stan
  if(phi_sd_stan > 0) {
    phi_copy = phi;
  } else {
    phi_copy = phi_mean_stan;
  }
  if(!is_inf(eta_param_stan)) {
    eta_copy = eta;
  } else {
    eta_copy = 1;
  }
  if(omega_sd_stan > 0) {
    omega_copy = omega;
  } else {
    omega_copy = exp(omega_mean_stan);
  }
  if(!is_inf(slab_dof_stan)) {
    slab_copy = slab;
  } else {
    slab_copy = slab_scale_stan^2;
  }
  theta_orig = 1 ./ sqrt(1 / slab_copy + ((1 - phi_copy) ./ (tau_glob^2 * sigma^2 * square(lambda_orig))));
  theta_aug = 1 ./ sqrt(1 / slab_copy + (1 ./ (tau_glob^2 * sigma^2 * square(lambda_aug))));
  beta_orig = theta_orig .* beta_raw_orig;
  beta_aug = theta_aug .* beta_raw_aug;
  beta = append_row(beta_orig, beta_aug);
  if(omega_sq_in_variance == 0) {
    hist_orig_scale = 1 ./ sqrt(scale_to_variance225 * (1 - phi_copy) + phi_copy / eta_copy);
  } else {
    hist_orig_scale = 1 ./ sqrt(scale_to_variance225 * (1 - phi_copy) + phi_copy / (eta_copy * omega_copy^2));
  }
  normalizing_cov = (quad_form_diag(alpha_prior_cov_stan,hist_orig_scale)) + tcrossprod(diag_post_multiply(aug_projection_stan,theta_aug));
  for(i in 1:p_stan) {
    normalizing_cov[i,i] = normalizing_cov[i,i] + theta_orig[i]^2;
  }
  normalized_beta = eigenvec_hist_var_stan * (beta_orig + aug_projection_stan * beta_aug - omega_copy * alpha_prior_mean_stan) ./ hist_orig_scale;
}
model {
  beta_raw_orig ~ normal(0.0, 1.0);
  beta_raw_aug ~ normal(0.0, 1.0);
  tau_glob ~ student_t(global_dof_stan, 0.0, 1.0);
  lambda_orig ~ student_t(local_dof_stan, 0.0, beta_orig_scale_stan);
  lambda_aug ~ student_t(local_dof_stan, 0.0, beta_aug_scale_stan);
  if(!is_inf(slab_dof_stan)) {
    slab ~ inv_gamma(slab_dof_stan / 2.0, slab_scale_stan^2 * slab_dof_stan / 2.0);
  } else {
    // slab is not used in this case but we need a proper prior to avoid sampling issues
    slab ~ inv_gamma(2.5, 2.5);
  }
  mu ~ logistic(0.0, mu_sd_stan);
  if(phi_sd_stan > 0 && phi_prior_type == 1) {
    phi ~ normal(phi_mean_stan, phi_sd_stan);
  } else if(phi_sd_stan > 0 && phi_prior_type == 0) {
    phi ~ beta(phi_beta_shape1, phi_beta_shape2);
  }
  if(!is_inf(eta_param_stan)) {
    eta ~ inv_gamma(eta_param_stan, eta_param_stan);
  } else {
    // eta is not used in this case but we need a proper prior to avoid sampling issues
    eta ~ inv_gamma(1.0, 1.0);
  }
  if(omega_sd_stan > 0) {
    omega ~ lognormal(omega_mean_stan, omega_sd_stan);
  } else {
    // omega is not used in this case but we need a proper prior to avoid sampling issues
    omega ~ lognormal(0.0, 1.0);
  }
  sigma ~ student_t(1, 0.0, 5.0);
  // Equation (S6) The next two lines together comprise the sensible adaptive prior contribution
  normalized_beta ~ normal(0.0, sqrt_eigenval_hist_var_stan);
  // Scaling normalized_beta to be independent ends up dropping a necessary determinant calculation: we add that back in here:
  target += -(1.0 * sum(log(hist_orig_scale)));
  // Z_SAB (Normalizing constant)
  target += -(1.0 * multi_normal_lpdf(omega_copy * alpha_prior_mean_stan|zero_vec, normalizing_cov));
  if(only_prior == 0) {
    y_stan ~ normal(mu + x_standardized_stan * beta, sigma);
  }
}
