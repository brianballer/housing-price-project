## ----setup, include=FALSE------------------------------------------------------------------------------------------------------------
knitr::opts_chunk$set(echo = FALSE, include=FALSE)

options(scipen=999)

library(glmnet)
library(gam)
library(rpart)
library(rpart.plot)
library(randomForest)
library(gbm)
library(earth)
options(java.parameters = "-Xmx12g")
library(rJava)
library(bartMachine)
library(e1071)
library(caret)
library(reshape2)


## ------------------------------------------------------------------------------------------------------------------------------------
knitr::purl("Models_Master_4.Rmd")


## ----Load Data Frame-----------------------------------------------------------------------------------------------------------------
df <- readRDS('data/train_4.rds')   ## Reads dataframe from shared drive



## ----One-Hot Encoding Df-------------------------------------------------------------------------------------------------------------
## update fact_vars and num_vars
col_class <- as.data.frame(lapply(df, class))
fact_vars <- names(df)[ sapply(df, is.factor) ] # Find column names of type 'Factor'
num_vars <- names(df)[ sapply(df, is.numeric)]  ## or num_vars <- which(sapply(df, is.integer))
print(paste("There are", length(fact_vars), "factor variables and", length(num_vars), "numeric (integer) variables"))

## One-Hot Encoding the Factors
df.onehot <- dummyVars("~.", data=df[,fact_vars])      ## dummyVars function from caret library
df.onehot <- data.frame(predict(df.onehot, newdata = df[,fact_vars]))

## Full dataframe of numerics and factors
dfoh <- cbind(df[,num_vars], df.onehot)
## Which columns are all zeros?
which(colSums(dfoh)<1)
## Delete the zero columns
dfoh <- dfoh[,-c(which(colSums(dfoh)<1))]


## Standardize X for inference with LASSO
dfoh[,-which(colnames(dfoh)=="SalePrice")] <- as.data.frame(scale(dfoh[,-which(colnames(dfoh)=="SalePrice")]))



## ----Training and Test Sets----------------------------------------------------------------------------------------------------------
## setting up training and test sets

set.seed(41)
trainrows <- sample(nrow(df), 0.7*nrow(df))

## non-onehot encoded sets
tr.df <- df[trainrows,]
te.df <- df[-trainrows,]

## one-hot encoded sets
tr.dfoh <- dfoh[trainrows,]
te.dfoh <- dfoh[-trainrows,]


## ----RMSE Function-------------------------------------------------------------------------------------------------------------------
## function used to for all models except boost

## log version -- calculates rmse when using log(SalePrice)
rmse <- function(mod, newdata, response) {
  rmse <- sqrt(mean((exp(predict(mod, newdata)) - response)^2))
  return(rmse)
}

## non-log version -- calculates rmse when using SalePrice
rmse.std <- function(mod, newdata, response) {
  rmse <- sqrt(mean((predict(mod, newdata) - response)^2))
  return(rmse)
}

## RMSE function for gbm (it requires to specify ## of trees in predict function) non-log version
rmse.boost <- function(mod, newdata, response, ntree) {
  rmse <- sqrt(mean((exp(predict(mod, newdata, n.trees=ntree)) - response)^2))
  return(rmse)
}

## Calculates RMSE the "Kaggle-way" (rmse of log(Predicted SalePrice) vs log(Observed SalePrice))
rmse.kaggle <- function(mod, newdata, response) {
  rmse <- sqrt(mean((predict(mod, newdata) - log(response))^2))
  return(rmse)
}



## ----Null Model----------------------------------------------------------------------------------------------------------------------
null.mod <- lm(log(SalePrice) ~ 1, data=tr.dfoh)   ## linear uses one-hot encoded df
#summary(lm.mod)

err.null <- c(rmse(null.mod, tr.dfoh, tr.dfoh$SalePrice), rmse(null.mod, te.dfoh, te.dfoh$SalePrice))
err.null


## ----Linear Model--------------------------------------------------------------------------------------------------------------------
lm.mod <- lm(log(SalePrice) ~., data=tr.dfoh)   ## linear uses one-hot encoded df
#summary(lm.mod)

err.lm <- c(rmse(lm.mod, tr.dfoh, tr.dfoh$SalePrice), rmse(lm.mod, te.dfoh, te.dfoh$SalePrice))
err.lm


## ----Model Assumptions, warning=FALSE, message=FALSE---------------------------------------------------------------------------------
## A check of model assumptions
par(mfrow=c(2,2))
plot(lm.mod)


## ----LASSO Model---------------------------------------------------------------------------------------------------------------------

## Setting up matrices for LASSO (using onehot df)
train_x <- as.matrix(subset(tr.dfoh, select = -SalePrice))
train_y <- as.matrix(subset(tr.dfoh, select = SalePrice))

test_x <- as.matrix(subset(te.dfoh, select = -SalePrice))
test_y <- as.matrix(subset(te.dfoh, select = SalePrice))

## Pick the best LASSO regression model using built-in K-fold CV
#set.seed(1)
#cv_lasso <- cv.glmnet(train_x, train_y, alpha=1)
cv_lasso <- cv.glmnet(train_x, log(train_y), alpha=1)     ## log(SalePrice) version

## Plot of MSE vs. lambda
plot(cv_lasso)

## Lambda with minimum MSE
cv_lasso$lambda.min

lasso_coefs <- coef(cv_lasso, s = "lambda.min")
length(lasso_coefs[lasso_coefs != 0])

#lasso.mod <- glmnet(train_x, train_y, alpha=1, lambda=cv_lasso$lambda.min)        ## non-log version
lasso.mod <- glmnet(train_x, log(train_y), alpha=1, lambda=cv_lasso$lambda.min)    ## log(SP) version

err.lasso <- c(rmse(lasso.mod, train_x, train_y), rmse(lasso.mod, test_x, test_y))
err.lasso


## ----Ridge Model---------------------------------------------------------------------------------------------------------------------
## Setting up matrices for ridge (using onehot df)
train_x <- as.matrix(subset(tr.dfoh, select = -SalePrice))
train_y <- as.matrix(subset(tr.dfoh, select = SalePrice))

test_x <- as.matrix(subset(te.dfoh, select = -SalePrice))
test_y <- as.matrix(subset(te.dfoh, select = SalePrice))

## Pick the best ridge regression model using built-in K-fold CV
set.seed(1)
#cv_ridge <- cv.glmnet(train_x, train_y, alpha=1)
cv_ridge <- cv.glmnet(train_x, log(train_y), alpha=0)     ## log(SalePrice) version

## Plot of MSE vs. lambda
plot(cv_ridge)

## Lambda with minimum MSE
cv_ridge$lambda.min

ridge_coefs <- coef(cv_ridge, s = "lambda.min")
length(ridge_coefs[ridge_coefs != 0])

#ridge.mod <- glmnet(train_x, train_y, alpha=1, lambda=cv_ridge$lambda.min)        ## non-log version
ridge.mod <- glmnet(train_x, log(train_y), alpha=1, lambda=cv_ridge$lambda.min)    ## log(SP) version

err.ridge <- c(rmse(ridge.mod, train_x, train_y), rmse(ridge.mod, test_x, test_y))
err.ridge


## ----Best Gam Model------------------------------------------------------------------------------------------------------------------
## Best GAM model from optimization
gam.mod <- gam(formula = log(SalePrice) ~ s(OverallQual, df = 5) + s(OverallCond, df = 5) + s(TotalSqFeet, df=5) + s(GarageYrBlt, df=5) + s(BsmtUnfSF, df=5) + s(FireplaceQu, df=5) + s(LotArea, df=5), data = tr.df, trace = FALSE)

err.gam <- c(rmse(gam.mod, tr.df, tr.df$SalePrice), rmse(gam.mod, te.df, te.df$SalePrice))
err.gam

#summary(gam.mod)


## ----Rpart Model---------------------------------------------------------------------------------------------------------------------
set.seed(1)
#rpart.mod <- rpart(SalePrice ~., data=tr.df)
rpart.mod <- rpart(log(SalePrice) ~., data=tr.df)    ##log(SalePrice) versions
printcp(rpart.mod)
minCP <- rpart.mod$cptable[which.min(rpart.mod$cptable[,"xerror"]),"CP"]    ##finds the minCP

## Prune tree to cp with minimum error
#par(mfrow=c(1,2))
plotcp(rpart.mod)
rpart.mod <- prune(rpart.mod, cp=minCP) 

## Plot tree diagram
rpart.plot(rpart.mod, main="Rpart Tree")

err.rpart <- c(rmse(rpart.mod, tr.df, tr.df$SalePrice), rmse(rpart.mod, te.df, te.df$SalePrice))
err.rpart


## ----Random Forest Optimization Function, eval=T-------------------------------------------------------------------------------------

## rf.cv() takes dataframe (data), hyperparameter to be tuned (hp) and values for hp (DOE)

rf.cv <- function(data, hp, DOE) { 
  nfolds <- 5              ## number of folds
  
  set.seed(1)
  data$fold <- sample(1:nfolds, nrow(data), replace = TRUE)        ## adds a column that assigns each row to a fold
  val.rmse <- vector()              ## initializes vector for to capture rmse of each fold
  rmse.vec <- vector()              ## initialize vector for capturing the mean(rmse) of each hyperparameter
  
  #DOE <- seq(10,ncol(data)-1-20,10)
  
  ## Outer loop cycles through hyperparameter values in DOE
  for (i in DOE) { 
    
    ## Inner loop cycles through the K-fold CV
    for (j in 1:nfolds) {
      train_df <- data[data$fold != j, -ncol(data)]   ## sets CV train df
      val_df <- data[data$fold == j, -ncol(data)]
      
      ## If statement selects hyperparameter to be tuned
      if (hp == "mtry") {
        #rf.mod <- randomForest(SalePrice ~., mtry=i, data=train_df)
        rf.mod <- randomForest(log(SalePrice) ~., mtry=i, data=train_df)  
      } else if (hp == "ntree") {
        rf.mod <- randomForest(log(SalePrice) ~., ntree=i, data=train_df)
      } else {
        stop('wrong hyperparameter')
      }
      
      val.rmse[j] <- rmse(rf.mod, val_df, val_df$SalePrice)   ## captures rmse for each "fold"
      
    }
    #print(val.rmse)
    rmse.vec[which(DOE == i)] <- (mean(val.rmse))     ## captures mean of all k-folds for each value in DOE
  }
  return(rmse.vec)    ## returns vector of rmse for each value in DOE
}



## ----RF Function Calls---------------------------------------------------------------------------------------------------------------
## Calls functions and prints elasped time
start.time <- Sys.time()

DOE.rf1 <- seq(10,ncol(tr.df)-1-20,10)
rf.rmse1 <- rf.cv(tr.df, "mtry", DOE.rf1)       ##this funtion returns a vector of mean(rmse) for each hyperparameter run
DOE.rf2 <- c(10, 100, 500, 1000, 2000)
rf.rmse2 <- rf.cv(tr.df, "ntree", DOE.rf2) 

end.time <- Sys.time()
time.taken <- end.time - start.time
time.taken


## ----Plot of RF CV Results-----------------------------------------------------------------------------------------------------------
par(mfrow=c(1,2))
plot(rf.rmse1 ~ DOE.rf1, main="RMSE w/ Random Forest Model", xlab="# of parameters at each split", ylab="RMSE")
plot(rf.rmse2 ~ DOE.rf2, main="RMSE w/ Random Forest Model", xlab="# of trees", ylab="RMSE")


## ----Best Random Forest Model--------------------------------------------------------------------------------------------------------
## Plots to tune hyperparameters
rf.mod <- randomForest(log(SalePrice) ~., mtry=30, ntree=2000, data=tr.df)
err.rf <- c(rmse(rf.mod, tr.df, tr.df$SalePrice),rmse(rf.mod, te.df, te.df$SalePrice))


## ----Random Forest Variable Importance Plot------------------------------------------------------------------------------------------
varImpPlot(rf.mod, main="Variable Importance Plot")


## ----Boosting Optimization Function, eval=T------------------------------------------------------------------------------------------

## boost.cv() takes dataframe (data), hyperparameter to be tuned (hp) and values for hp (DOE)

boost.cv <- function(data, hp, DOE) { 
  nfolds <- 5
  
  set.seed(1)
  data$fold <- sample(1:nfolds, nrow(data), replace = TRUE)        ## adds a column that assigns each row to a fold
  val.rmse <- vector()              ## initializes vector for results
  rmse.vec <- vector()  ## initialize vector for below chart
  
  ntree <- 1000         ## sets number of trees for model
  
  for (i in DOE) { 
    
    for (j in 1:nfolds) {
      train_df <- data[data$fold != j, -ncol(data)]
      val_df <- data[data$fold == j, -ncol(data)]
      
      if (hp == "interaction.depth") {
        boost.mod <- gbm(log(SalePrice) ~., data=train_df, distribution="gaussian",n.trees=ntree, interaction.depth=i)
      } else if (hp == "shrinkage") {
        boost.mod <- gbm(log(SalePrice) ~., data=train_df, distribution="gaussian",n.trees=ntree, interaction.depth=3, shrinkage=i)
      } else if (hp == "n.trees") {
        boost.mod <- gbm(log(SalePrice) ~., data=train_df, distribution="gaussian",n.trees=i, interaction.depth=3, shrinkage=.1)
      } else {
        stop('wrong hyperparameter')
      }
      
      val.rmse[j] <- rmse.boost(boost.mod, val_df, val_df$SalePrice, ntree)
      
    }
    #print(val.rmse)
    #print(paste(mean(val.rmse), sd(val.rmse)))
    rmse.vec[which(DOE == i)] <- mean(val.rmse)          ## because index has switched to non-integer sequence
  }
  return(rmse.vec)
}


## ----Boost Function Call-------------------------------------------------------------------------------------------------------------
## Calls functions and prints elasped time
start.time <- Sys.time()

DOE.boost1 <- c(1,3,4,5,6)
boost1.rmse <- boost.cv(tr.df, "interaction.depth", DOE.boost1)
DOE.boost2 <- c(.2, .1, 0.01, 0.005)
boost2.rmse <- boost.cv(tr.df, "shrinkage", DOE.boost2)
DOE.boost3 <- c(500, 1000, 2000, 3000, 5000)
boost3.rmse <- boost.cv(tr.df, "n.trees", DOE.boost3)

end.time <- Sys.time()
time.taken <- end.time - start.time
time.taken


## ----Boosting CV Optimization Plots--------------------------------------------------------------------------------------------------
## Plots to tune hyperparameters
par(mfrow=c(1,3))
plot(boost1.rmse ~ DOE.boost1, main="Interaction Depth", xlab="Interaction Depth", ylab="RMSE")
plot(boost2.rmse ~ DOE.boost2, main="Shrinkage Factor", xlab="Shrinkage Factor", ylab="RMSE")
plot(boost3.rmse ~ DOE.boost3, main="Number of Trees", xlab="Number of Trees", ylab="RMSE")


## ----Best Boosting Model-------------------------------------------------------------------------------------------------------------
## Run gbm and get rmse with best hyperparameters
set.seed(1)
ntree <- 2000
boost.mod <- gbm(log(SalePrice) ~., data=tr.df, distribution="gaussian",n.trees=ntree, interaction.depth=1, shrinkage=0.01)

err.boost <- c(rmse.boost(boost.mod, tr.df, tr.df$SalePrice, ntree), rmse.boost(boost.mod, te.df, te.df$SalePrice, ntree))
err.boost


## ----Earth Models--------------------------------------------------------------------------------------------------------------------
## Earth model w/o pruning
#earth.mod <- earth(SalePrice ~., data=tr.df)
earth.mod <- earth(log(SalePrice) ~., data=tr.df) 

## Earth model w/ pruning
#earth.mod <- earth(log(SalePrice) ~., data=tr.df, pmethod="none")

err.earth <- c(rmse(earth.mod, tr.df, tr.df$SalePrice),rmse(earth.mod, te.df, te.df$SalePrice))


## ----BART Optimization Function, eval=T, message=F, warning=F------------------------------------------------------------------------

## bart.cv() takes dataframe (data), hyperparameter to be tuned (hp) and valuse for hp (DOE)

bart.cv <- function(data, hp, DOE) { 
  nfolds <- 5              ## number of folds
  
  set.seed(1)
  data$fold <- sample(1:nfolds, nrow(data), replace = TRUE)        ## adds a column that assigns each row to a fold
  val.rmse <- vector()              ## initializes vector for to capture rmse of each fold
  rmse.vec <- vector()  ## initialize vector for capturing the mean(rmse) of each hyperparameter
  q <- c(.9, .99, .75)
  nu <- c(3, 3, 10)

  for (i in DOE) { 
    
    for (j in 1:nfolds) {
      train_df <- data[data$fold != j, -ncol(data)]   ## sets CV train df
      val_df <- data[data$fold == j, -ncol(data)]
      tr.df.Bart <- subset(train_df, select = -c(SalePrice))
      val.df.Bart <- subset(val_df, select = -c(SalePrice))
      
      if (hp == "num_trees") { 
        bart.mod <- bartMachine(X=tr.df.Bart, y=log(train_df$SalePrice), seed = 1, num_trees=i)
        } else if (hp == "k") {
        bart.mod <- bartMachine(X=tr.df.Bart, y=log(train_df$SalePrice), seed = 1, k = i)
        } else if (hp == "sigma") {
        bart.mod <- bartMachine(X=tr.df.Bart, y=log(train_df$SalePrice), seed = 1, q = q[i], nu = nu[i])
        } else {
        stop('wrong hyperparameter')
        }
      
      val.rmse[j] <- rmse(bart.mod, val.df.Bart, val_df$SalePrice)
      
    }
    #print(val.rmse)
    rmse.vec[which(DOE == i)] <- (mean(val.rmse))
  }
  return(rmse.vec)
}




## ----BART Function Calls-------------------------------------------------------------------------------------------------------------
## Calls functions and prints elasped time
start.time <- Sys.time()

DOE.bart1 <- c(50, 100, 1000)
bart1.rmse <- bart.cv(tr.df, "num_trees", DOE.bart1)    ##this funtion returns a vector of mean(rmse) for each hyperparameter run
DOE.bart2 <- c(1, 2, 3, 4, 5)
bart2.rmse <- bart.cv(tr.df, "k", DOE.bart2)    ##this funtion returns a vector of mean(rmse) for each hyperparameter run
DOE.bart3 <- c(1,2,3)     ### this corresponds to 'default', 'aggressive', 'conservative' WRT the sigma prior
bart3.rmse <- bart.cv(tr.df, "sigma", DOE.bart3)    ##this funtion returns a vector of mean(rmse) for each hyperparameter run

end.time <- Sys.time()
time.taken <- end.time - start.time
time.taken


## ----BART CV Results-----------------------------------------------------------------------------------------------------------------
par(mfrow=c(1,3))
plot(bart1.rmse ~ DOE.bart1, main="RMSE w/ BART Model", xlab="Number of Trees", ylab="RMSE")
plot(bart2.rmse ~ DOE.bart2, main="RMSE w/ BART Model", xlab="k", ylab="RMSE")
plot(bart3.rmse ~ DOE.bart3, main="RMSE w/ BART Model", xaxt="n", xlab="Sigma Prior", ylab="RMSE")
axis(1, at = DOE.bart3, labels = c("Default", "Aggressive", "Conservative"), las = 1, cex.axis=0.7)


## ----RMSE for Best BART mod----------------------------------------------------------------------------------------------------------
## BART setup
tr.df.Bart <- subset(tr.df, select = -c(SalePrice))
te.df.Bart <- subset(te.df, select = -c(SalePrice))

## Using hyperparameters from CV
bart.mod <- bartMachine(X=tr.df.Bart, y=log(tr.df$SalePrice), num_trees=1000, k=3, q = .9, nu = 3, seed = 1)

## Using defaults (i.e. to skip CV)
#bart.mod <- bartMachine(X=tr.df.Bart, y=log(tr.df$SalePrice), seed = 1)

err.bart <- c(rmse(bart.mod, tr.df.Bart, tr.df$SalePrice),rmse(bart.mod, te.df.Bart, te.df$SalePrice)); err.bart

## "var_selection_by_permute" was only working in console vice Markdown
#investigate_var_importance(bart.mod, num_replicates_for_avg=2)



## ----SVR Optimization----------------------------------------------------------------------------------------------------------------
## Tuning of SVR model

start.time <- Sys.time()
tune.out = tune(svm, log(SalePrice) ~., data=tr.df, kernel="polynomial", ranges=list(epsilon=seq(0,.9,0.1), cost=seq(1,101,5)))
end.time <- Sys.time()
time.taken <- end.time - start.time
time.taken

plot(tune.out)
print(tune.out)

#summary(tune.out)


## ----Best SVR Model------------------------------------------------------------------------------------------------------------------
svr.mod <- tune.out$best.model

summary(svr.mod)

err.svr <- c(rmse(svr.mod, tr.df, tr.df$SalePrice), rmse(svr.mod, te.df, te.df$SalePrice))
err.svr


## ----Summary Table, include=TRUE-----------------------------------------------------------------------------------------------------
## Makes df of error results
err.df <- as.data.frame(rbind(err.lm, err.lasso, err.rpart, err.rf, err.boost, err.earth, err.bart, err.svr, err.null))
colnames(err.df) <- c("Training RMSE", "Test RMSE")
err.df[order(err.df$`Test RMSE`),]


## ----Predicted vs. Actual------------------------------------------------------------------------------------------------------------
plot(te.df$SalePrice, exp(predict(lasso.mod, test_x)), main="How Well Does the Model Predict?", xlab="Observed Sales Price", ylab="Predicted Sales Price")
abline(a=0, b=1, col="red")


## ----Variable Importance-------------------------------------------------------------------------------------------------------------
## Lasso
var_imp <- as.data.frame(as.matrix(lasso_coefs))

## MARS
evimp(earth.mod)
plotmo(earth.mod)


## ----Earth Robustness with Different Seeds-------------------------------------------------------------------------------------------
erob.rmse <- vector()

## Loop to calculate RMSE at different seeds
for (i in 1:100) {
  set.seed(i)
  trainrows <- sample(nrow(df), 0.7*nrow(df))
  
  ## non-onehot encoded sets
  tr.df <- df[trainrows,]
  te.df <- df[-trainrows,]
  
  ## Earth model w/o pruning
  #earth.mod <- earth(SalePrice ~., data=tr.df)
  earth.mod <- earth(log(SalePrice) ~ ., data=tr.df, pmethod="backward") 
  #print(evimp(earth.mod)[1:5,0])
  
  ## Earth model w/ pruning
  #earth.mod <- earth(log(SalePrice) ~., data=tr.df, pmethod="none")
  
  erob.rmse[i] <- rmse(earth.mod, te.df, te.df$SalePrice)
}
## Vector all RMSEs
erob.rmse
mean(erob.rmse)
sd(erob.rmse)


## ----LASSO Model with Different Seeds------------------------------------------------------------------------------------------------
## Standardize X for inference with LASSO
# dfoh[,-which(colnames(dfoh)=="SalePrice")] <- as.data.frame(scale(dfoh[,-which(colnames(dfoh)=="SalePrice")]))
# 
# #dfoh <- as.data.frame(apply(dfoh, 2, function(x){(x-mean(x))/sd(x)}))
# 
# ## Check to ensure no constant variance columns (sd=0)
# which(is.na(apply(dfoh, 2, sd)))

lrob.rmse <- vector()

## Loop to calculate RMSE at different seeds
for (i in 1:100) {
  set.seed(i)
  trainrows <- sample(nrow(df), 0.7*nrow(df))
  
  ## one-hot encoded sets
  tr.dfoh <- dfoh[trainrows,]
  te.dfoh <- dfoh[-trainrows,]
  
  ## Setting up matrices for LASSO (using onehot df)
  train_x <- as.matrix(subset(tr.dfoh, select = -SalePrice))
  train_y <- as.matrix(subset(tr.dfoh, select = SalePrice))
  
  test_x <- as.matrix(subset(te.dfoh, select = -SalePrice))
  test_y <- as.matrix(subset(te.dfoh, select = SalePrice))
  
  ## Pick the best LASSO regression model using built-in K-fold CV
  #set.seed(1)
  #cv_lasso <- cv.glmnet(train_x, train_y, alpha=1)
  cv_lasso <- cv.glmnet(train_x, log(train_y), alpha=1, standardize=FALSE)     ## log(SalePrice) version
  
  ## Plot of MSE vs. lambda
  #plot(cv_lasso)
  
  ## Lambda with minimum MSE
  cv_lasso$lambda.min
  
  lasso_coefs <- coef(cv_lasso, s = "lambda.min")
  #print(length(lasso_coefs[lasso_coefs != 0]))
  
  #lasso.mod <- glmnet(train_x, train_y, alpha=1, lambda=cv_lasso$lambda.min)        ## non-log version
  lasso.mod <- glmnet(train_x, log(train_y), alpha=1, lambda=cv_lasso$lambda.min, standardize=FALSE)    ## log(SP) version
  
  lrob.rmse[i] <- rmse(lasso.mod, test_x, test_y)
}  
## Vector all RMSEs from LASSO
lrob.rmse
mean(lrob.rmse)
sd(lrob.rmse)


## ----Histogram of MARS and LASSO-----------------------------------------------------------------------------------------------------
## Combining LASSO and MARS RMSE vectors
rob <- as.data.frame(cbind(erob.rmse, lrob.rmse))
colnames(rob) <- c("MARS", "LASSO")
## Switching from "wide" dataframe to "tall" dataframe for histogram
mrob <- melt(rob)

## Histogram of two vectors overlaid
gg <- ggplot(mrob, aes(x = value, color=variable))  #color= set border color

gg + geom_histogram(aes(fill=variable), position="dodge", binwidth=1000, color="black") +  #fill = fill color, #color= border color
  labs(title="Model Performance Across 100 Different Seeds", y=NULL, x="RMSE (in dollars)")


## ----Hypothesis Testing of Two Means-------------------------------------------------------------------------------------------------
## t-test of MARS and LASSO RMSEs
t.test(erob.rmse, lrob.rmse)


## ----Datasave, echo=F----------------------------------------------------------------------------------------------------------------
## Outputs error table to file
saveRDS(err.df[order(err.df$`Test RMSE`),], file= 'data/RMSE_table_4.rds')
save.image('data/Model_4.RData')

