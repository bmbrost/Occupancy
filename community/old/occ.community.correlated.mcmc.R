occ.community.correlated.mcmc <- function(Y,J,W,X,priors,start,tune,n.mcmc,adapt=TRUE){

	#
	#  	Brian Brost (21 JUN 2017)
	#	
	#	Community occupancy model with correlated detection and occupancy intercepts
	#
	#  	Y: 
	#	J:
	# 	W: 
	#  	X: 
	#	priors:
	#	start:
	#	tune:
	#	n.mcmc:
	#	adapt:
	#
	
	
	###
	###  Libraries and Subroutines
	###
	
	library(mvtnorm)
	
	truncnormsamp <- function(mu,sig2,low,high,nsamp){
		flow <- pnorm(low,mu,sqrt(sig2)) 
		fhigh <- pnorm(high,mu,sqrt(sig2)) 
		u <- runif(nsamp) 
		tmp <- flow+u*(fhigh-flow)
		x <- qnorm(tmp,mu,sqrt(sig2))
		x
	}
	
	expit <- function(logit){
		exp(logit)/(1+exp(logit)) 
	}
	
	logit <- function(expit){
		log(expit/(1-expit))
	}

	get.tune <- function(tune,keep,k,target=0.44){  # adaptive tuning
		a <- min(0.01,1/sqrt(k))
		# a <- min(0.025,1/sqrt(k))
		exp(ifelse(keep<target,log(tune)-a,log(tune)+a))
	}


	###
	###  Create Variables 
	###
# browser()
	n <- nrow(Y)
	R <- ncol(Y)
	qX <- ncol(X)
	qW <- ncol(W)
	v <- matrix(0,n,R)

	
	###
	###  Priors
	###
		
	S0 <- priors$S0
	nu <- priors$nu
	Sigma.0 <- diag(2)*priors$sigma.mu.0^2
	Sigma.0.inv <- solve(Sigma.0)
	Sigma.mu.beta <- diag(qX-1)*priors$sigma.mu.beta^2
	Sigma.mu.beta.inv <- solve(Sigma.mu.beta)	
	
	
	###
	###  Starting Values 
	###

	alpha <- matrix(start$alpha,qW,n)
	beta <- matrix(start$beta,qX,n)
	mu.alpha <- matrix(start$mu.alpha,qW,1)	
	mu.beta <- matrix(start$mu.beta,qX,1)	
	p <- expit(alpha)
	z <- start$z
	mu.0 <- matrix(c(mu.alpha[1],mu.beta[1]),2,1)
	
	Sigma <- start$Sigma
	Sigma.inv <- solve(Sigma)
	
	Sigma.beta <- diag(qX-1)*start$sigma.beta^2
	Sigma.beta.inv <- solve(Sigma.beta)	
	
	
	###
	###  Create receptacles for output
	###

	alpha.save <- array(0,c(n.mcmc,qW,n))
	beta.save <- array(0,c(n.mcmc,qX,n))
	z.mean <- matrix(0,n,R)
	mu.alpha.save <- matrix(0,n.mcmc,qW)
	mu.beta.save <- matrix(0,n.mcmc,qX)
	Sigma.save <- array(0,dim=c(2,2,n.mcmc))
	sigma.beta.save <- numeric(n.mcmc)
	N.save <- matrix(0,n.mcmc,R)

	keep <- list(alpha=0,beta=0)
	keep.tmp <- keep
	Tb <- 50  # frequency of adaptive tuning


	###
	###  Begin MCMC Loop 
	###
	
	for(k in 1:n.mcmc){
		if(k%%1000==0) cat(k," "); flush.console()

		###
		### Adaptive tuning
		###
		
		if(adapt==TRUE & k%%Tb==0) {  # Adaptive tuning
			keep.tmp <- lapply(keep.tmp,function(x) x/(Tb*n))
			tune$alpha <- get.tune(tune$alpha,keep.tmp$alpha,k)
			tune$beta <- get.tune(tune$beta,keep.tmp$beta,k)
			keep.tmp <- lapply(keep.tmp,function(x) x*0)
	   	} 				

# browser()
		A <- solve(t(X[,-1])%*%X[,-1]+Sigma.beta.inv)  # for update of beta		
		alpha.star <- alpha
		alpha.star[1,] <- rnorm(n,alpha[1,],tune$alpha)  # proposals for alpha_0
		beta.star <- beta
		beta.star[1,] <- rnorm(n,beta[1,],tune$beta)  # proposals for beta_0
		p.star <- expit(alpha.star)  # proposals for p_i
		
		for (i in 1:n){  # loop through species
# i <- 1
			###
			###  Sample v (auxilliary variable for z) 
			###
		
			z0 <- z[i,]==0
			z1 <- z[i,]==1
			v[i,z0] <- truncnormsamp(matrix(X[z0,],,qX)%*%beta[,i],1,-Inf,0,sum(z0))
			v[i,z1] <- truncnormsamp(matrix(X[z1,],,qX)%*%beta[,i],1,0,Inf,sum(z1))


			###
	  		###  Sample alpha_0 and updata p_i
		  	###
# browser()
			z1 <- z[i,]==1	
		 	mh.star <- sum(dbinom(Y[i,z1],J[z1],p.star[i],log=TRUE))+
				dmvnorm(c(alpha.star[1,i],beta[1,i]),mu.0,Sigma,log=TRUE)
		 	mh.0 <- sum(dbinom(Y[i,z1],J[z1],p[i],log=TRUE))+
				dmvnorm(c(alpha[1,i],beta[1,i]),mu.0,Sigma,log=TRUE)
			if(exp(mh.star-mh.0) > runif(1)){
				alpha[1,i] <- alpha.star[1,i]
				p[i] <- p.star[i]
				keep$alpha <- keep$alpha+1
				keep.tmp$alpha <- keep.tmp$alpha+1
		  	}			
			

			###
			### Sample beta_0
			###
# browser()	
			mh.star <- sum(dnorm(v[i,],X%*%beta.star[,i],1,log=TRUE))+
				dmvnorm(c(alpha[1,i],beta.star[1,i]),mu.0,Sigma,log=TRUE)
			mh.0 <- sum(dnorm(v[i,],X%*%beta[,i],1,log=TRUE))+
				dmvnorm(c(alpha[1,i],beta[1,i]),mu.0,Sigma,log=TRUE)
			if(exp(mh.star-mh.0) > runif(1)){
				beta[1,i] <- beta.star[1,i]
				keep$beta <- keep$beta+1
				keep.tmp$beta <- keep.tmp$beta+1
		  	}			

			
			###
			###  Sample beta_i and update psi_i
			###
# browser()	
			b <- t(X[,-1])%*%(v[i,]-beta[1,i])+Sigma.beta.inv%*%mu.beta[-1,1]			
			beta[-1,i] <- A%*%b+t(chol(A))%*%matrix(rnorm(qX-1),qX-1,1)
			psi[i,] <- pnorm(X%*%beta[,i])			

	
			###
			###  Sample z 
			###
# browser()			
			idx <- Y[i,]==0
			p1 <- psi[i,]*p[i]^Y[i,]*(1-p[i])^(J-Y[i,])
			p0 <- 1-psi[i,]
			psi.tmp <- p1/(p1+p0)
			z[i,idx] <- rbinom(sum(idx),1,psi.tmp[idx])		

		}  # end loop through species
		

		###
		###  Sample mu.0
		###
# browser()
		beta.sum <- rowSums(beta)
		alpha.sum <- rowSums(alpha)
		A.inv <- solve(n*Sigma.inv+Sigma.0.inv)
		b <- Sigma.inv%*%c(alpha.sum[1],beta.sum[1])
	    mu.0 <- matrix(A.inv%*%(b)+t(chol(A.inv))%*%matrix(rnorm(2),2,1),2,1)
		mu.alpha[1,1] <- mu.0[1,1]	
		mu.beta[1,1] <- mu.0[2,1]

		###
		###  Sample mu.beta
		###

		A.inv <- solve(n*Sigma.beta.inv+Sigma.mu.beta.inv)
		b <- Sigma.beta.inv%*%beta.sum[-1]
	    mu.beta[-1,1] <- A.inv%*%b+t(chol(A.inv))%*%matrix(rnorm(qX-1),qX-1,1)
		# mu.beta <- t(rmvnorm(1,A.inv%*%b,A.inv))
	

		###
		### Sample Sigma
		###
# browser()		
		tmp <- apply(cbind(alpha[1,],beta[1,]),1,function(x) crossprod(t(x-mu.0)))
		Sn <- S0+matrix(rowSums(tmp),2,2)
		Sigma <- solve(rWishart(1,nu+n,solve(Sn))[,,1])
		Sigma.inv <- solve(Sigma)
		

		###
		###  Sample sigma.beta 
		###	
# browser()
		tmp <- apply(beta,2,function(x) x-mu.beta)^2
		tmp <- sum(tmp[-1,])
		r.tmp <- 1/(tmp/2+1/priors$r)
		q.tmp <- ((qX-1)*n)/2+priors$q
		sigma.beta <- 1/rgamma(1,q.tmp,,r.tmp)
		Sigma.beta <- diag(qX-1)*sigma.beta
		Sigma.beta.inv <- solve(Sigma.beta)				
		sigma.beta <- sqrt(sigma.beta)


		###
		###  Save samples 
		###
		
		alpha.save[k,,] <- alpha
		beta.save[k,,] <- beta
		z.mean <- z.mean+z/n.mcmc
		mu.alpha.save[k,] <- mu.alpha
		mu.beta.save[k,] <- mu.beta
		Sigma.save[,,k] <- Sigma
		sigma.beta.save[k] <- sigma.beta
		N.save[k,] <- colSums(z)
	
		}
	cat("\n")
	
	###
	###  Write output 
	###
	
	# keep$alpha <- keep$alpha/n
	keep <- lapply(keep,function(x) x/(n.mcmc*n))
	end <- list(alpha=alpha,beta=beta,z=z,mu.alpha=mu.alpha,  # ending values
		mu.beta=mu.beta,Sigma=Sigma,sigma.beta=sigma.beta)

	list(alpha=alpha.save,beta=beta.save,z.mean=z.mean,mu.alpha=mu.alpha.save,mu.beta=mu.beta.save,
		Sigma=Sigma.save,sigma.beta=sigma.beta.save,N=N.save,keep=keep,
		Y=Y,W=W,X=X,priors=priors,start=start,tune=tune,n.mcmc=n.mcmc,adapt=adapt)
}



# occ.community.correlated.mcmc <- function(Y,J,W=NULL,X,priors,start,tune,n.mcmc,adapt=TRUE){

	# #
	# #  	Brian Brost (20 JUN 2017)
	# #	
	# #	Basic community occupancy model
	# #
	# #  	Y: 
	# #	J:
	# # 	W: 
	# #  	X: 
	# #	priors:
	# #	start:
	# #	tune:
	# #	n.mcmc:
	# #	adapt:
	# #
	
	
	# ###
	# ###  Libraries and Subroutines
	# ###
	
	# library(mvtnorm)
	
	# truncnormsamp <- function(mu,sig2,low,high,nsamp){
		# flow <- pnorm(low,mu,sqrt(sig2)) 
		# fhigh <- pnorm(high,mu,sqrt(sig2)) 
		# u <- runif(nsamp) 
		# tmp <- flow+u*(fhigh-flow)
		# x <- qnorm(tmp,mu,sqrt(sig2))
		# x
	# }
	
	# expit <- function(logit){
		# exp(logit)/(1+exp(logit)) 
	# }
	
	# logit <- function(expit){
		# log(expit/(1-expit))
	# }

	# get.tune <- function(tune,keep,k,target=0.44){  # adaptive tuning
		# a <- min(0.01,1/sqrt(k))
		# # a <- min(0.025,1/sqrt(k))
		# exp(ifelse(keep<target,log(tune)-a,log(tune)+a))
	# }


	# ###
	# ###  Create Variables 
	# ###
# # browser()
	# n <- nrow(Y)
	# R <- ncol(Y)
	# qX <- ncol(X)
	# qW <- ifelse(is.null(W),1,ncol(W))
	# v <- matrix(0,n,R)
	# u <- numeric(n)

	
	# ###
	# ###  Priors
	# ###
		
	# S0 <- priors$S0
	# nu <- priors$nu
	# Sigma.0 <- diag(2)*priors$sigma.0^2
	# Sigma.0.inv <- solve(Sigma.0)
	# Sigma.mu.beta <- diag(qX)*priors$sigma.mu.beta^2
	# Sigma.mu.beta.inv <- solve(Sigma.mu.beta)	
	
	
	# ###
	# ###  Starting Values 
	# ###

	# alpha.0 <- c(start$alpha.0)
	# beta.0 <- c(start$beta.0)
	# beta <- start$beta
	# mu.0 <- matrix(start$mu.0,2,1)	
	# mu.beta <- matrix(start$mu.beta,qX,1)	
	# p <- expit(alpha.0)
	# z <- start$z
	
	# Sigma <- start$Sigma
	# Sigma.inv <- solve(Sigma)
	# Sigma.beta <- diag(qX)*start$sigma.beta^2
	# Sigma.beta.inv <- solve(Sigma.beta)	
	
	
	# ###
	# ###  Create receptacles for output
	# ###

	# alpha.0.save <- matrix(0,n.mcmc,n)
	# beta.0.save <- matrix(0,n.mcmc,n)
	# beta.save <- array(0,c(n,qX,n.mcmc))
	# z.mean <- matrix(0,n,R)
	# mu.0.save <- matrix(0,n.mcmc,2)
	# mu.beta.save <- matrix(0,n.mcmc,qX)
	# Sigma.save <- array(0,dim=c(2,2,n.mcmc))
	# sigma.beta.save <- numeric(n.mcmc)
	# N.save <- matrix(0,n.mcmc,R)

	# keep <- list(alpha.0=0,beta.0=0)
	# keep.tmp <- keep
	# Tb <- 50  # frequency of adaptive tuning


	# ###
	# ###  Begin MCMC Loop 
	# ###
	
	# for(k in 1:n.mcmc){
		# if(k%%1000==0) cat(k," "); flush.console()

		# ###
		# ### Adaptive tuning
		# ###
		
		# if(adapt==TRUE & k%%Tb==0) {  # Adaptive tuning
			# keep.tmp <- lapply(keep.tmp,function(x) x/(Tb*n))
			# tune$alpha.0 <- get.tune(tune$alpha.0,keep.tmp$alpha.0,k)
			# tune$beta.0 <- get.tune(tune$beta.0,keep.tmp$beta.0,k)
			# keep.tmp <- lapply(keep.tmp,function(x) x*0)
	   	# } 	
	   	
	   			
		# ###
		# ###  Sample v (auxilliary variable for z) 
		# ###
# # browser()		
		# for(i in 1:R){
			# # i <- 1
			# z0 <- z[,i]==0
			# z1 <- z[,i]==1
			# v[z0,i] <- truncnormsamp(beta.0[z0]+matrix(X[i,],,qX)%*%beta[,z0],1,-Inf,0,sum(z0))
			# v[z1,i] <- truncnormsamp(beta.0[z1]+matrix(X[i,],,qX)%*%beta[,z1],1,0,Inf,sum(z1))
		# }

		# # library(msm)	
		# # v[z1] <- rtnorm(sum(z1),(X%*%beta)[z1],lower=0)
		# # v[z0] <- rtnorm(sum(z0),(X%*%beta)[z0],upper=0)		


		# A <- solve(t(X)%*%X+Sigma.beta.inv)  # for update of beta
		# alpha.0.star <- rnorm(n,alpha.0,tune$alpha.0)  # proposals for alpha_0
		# beta.0.star <- rnorm(n,beta.0,tune$beta.0)  # proposals for beta_0
		# p.star <- expit(alpha.0.star)  # proposals for p_i
		
		# for (i in 1:n){  # loop through species

			# ###
	  		# ###  Sample alpha_i and updata p_i
		  	# ###
# # browser()
			# z1 <- z[i,]==1	
		 	# mh.star <- sum(dbinom(Y[i,z1],J[z1],p.star[i],log=TRUE))+
				# dmvnorm(c(alpha.0.star[i],beta.0[i]),mu.0,Sigma,log=TRUE)
		 	# mh.0 <- sum(dbinom(Y[i,z1],J[z1],p[i],log=TRUE))+
				# dmvnorm(c(alpha.0[i],beta.0[i]),mu.0,Sigma,log=TRUE)
			# if(exp(mh.star-mh.0) > runif(1)){
				# alpha.0[i] <- alpha.0.star[i]
				# p[i] <- p.star[i]
				# keep$alpha.0 <- keep$alpha.0+1
				# keep.tmp$alpha.0 <- keep.tmp$alpha.0+1
		  	# }			
			

			# ###
			# ### Sample beta_0
			# ###
# # browser()			
			# mh.star <- sum(dnorm(v[i,],beta.0.star[i]+X%*%beta[,i],1,log=TRUE))+
				# dmvnorm(c(alpha.0[i],beta.0.star[i]),mu.0,Sigma,log=TRUE)
			# mh.0 <- sum(dnorm(v[i,],beta.0[i]+X%*%beta[,i],1,log=TRUE))+
				# dmvnorm(c(alpha.0[i],beta.0[i]),mu.0,Sigma,log=TRUE)
			# if(exp(mh.star-mh.0) > runif(1)){
				# beta.0[i] <- beta.0.star[i]
				# keep$beta.0 <- keep$beta.0+1
				# keep.tmp$beta.0 <- keep.tmp$beta.0+1
		  	# }			

			
			# ###
			# ###  Sample beta_i and update psi_i
			# ###
# # browser()	
			# b <- t(X)%*%(v[i,]-beta.0[i])+Sigma.beta.inv%*%mu.beta			
			# beta[,i] <- A%*%b+t(chol(A))%*%matrix(rnorm(qX),qX,1)
			# psi[i,] <- pnorm(beta.0[i]+X%*%beta[,i])			

	
			# ###
			# ###  Sample z 
			# ###
# # browser()			
			# idx <- Y[i,]==0
			# p1 <- psi[i,]*p[i]^Y[i,]*(1-p[i])^(J-Y[i,])
			# p0 <- 1-psi[i,]
			# psi.tmp <- p1/(p1+p0)
			# z[i,idx] <- rbinom(sum(idx),1,psi.tmp[idx])		

		# }  # end loop through species
		

		# ###
		# ###  Sample mu.0
		# ###
# # browser()
		# A.inv <- solve(n*Sigma.inv+Sigma.0.inv)
		# b <- Sigma.inv%*%c(sum(alpha.0),sum(beta.0))
	    # mu.0 <- A.inv%*%(b)+t(chol(A.inv))%*%matrix(rnorm(2),2,1)


		# ###
		# ###  Sample mu.beta
		# ###

		# A.inv <- solve(n*Sigma.beta.inv+Sigma.mu.beta.inv)
		# b <- Sigma.beta.inv%*%rowSums(beta)
	    # mu.beta <- A.inv%*%b+t(chol(A.inv))%*%matrix(rnorm(qX),qX,1)
		# # mu.beta <- t(rmvnorm(1,A.inv%*%b,A.inv))
	

		# ###
		# ### Sample Sigma
		# ###
# # browser()		
		# tmp <- apply(cbind(alpha.0,beta.0),1,function(x) crossprod(t(x-mu.0)))
		# Sn <- S0+matrix(rowSums(tmp),2,2)
		# Sigma <- solve(rWishart(1,nu+n,solve(Sn))[,,1])
		# Sigma.inv <- solve(Sigma)
		

		# ###
		# ###  Sample sigma.beta 
		# ###	
# # browser()
		# tmp <- sum(apply(beta,2,function(x) x-mu.beta)^2)
		# r.tmp <- 1/(tmp/2+1/priors$r)
		# q.tmp <- (qX*n)/2+priors$q
		# sigma.beta <- 1/rgamma(1,q.tmp,,r.tmp)
		# Sigma.beta <- diag(qX)*sigma.beta
		# Sigma.beta.inv <- solve(Sigma.beta)				
		# sigma.beta <- sqrt(sigma.beta)


		# ###
		# ###  Save samples 
		# ###

		# alpha.0.save[k,] <- alpha.0
		# beta.0.save[k,] <- beta.0
		# beta.save[,,k] <- t(beta)
		# z.mean <- z.mean+z/n.mcmc
		# mu.0.save[k,] <- mu.0
		# mu.beta.save[k,] <- mu.beta
		# Sigma.save[,,k] <- Sigma
		# sigma.beta.save[k] <- sigma.beta
		# N.save[k,] <- colSums(z)
	
		# }
	# cat("\n")
	
	# ###
	# ###  Write output 
	# ###
	
	# # keep$alpha <- keep$alpha/n
	# keep <- lapply(keep,function(x) x/(n.mcmc*n))
	# end <- list(alpha.0=alpha.0,beta.0=beta.0,beta=beta,z=z,mu.0=mu.0,  # ending values
		# mu.beta=mu.beta,Sigma=Sigma,sigma.beta=sigma.beta)

	# list(alpha.0=alpha.0.save,beta.0=beta.0.save,beta=beta.save,z.mean=z.mean,
		# mu.0=mu.0.save,mu.beta=mu.beta.save,Sigma=Sigma.save,sigma.beta=sigma.beta.save,N=N.save,
		# keep=keep,Y=Y,W=W,X=X,priors=priors,start=start,tune=tune,n.mcmc=n.mcmc,adapt=adapt)
# }

