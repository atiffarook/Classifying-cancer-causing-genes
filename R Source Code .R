# R Source Code

## LOADING REQUIRED PACKAGES 
require(foreign)
require(nnet)
require(reshape2)
library(class)
library(MASS)
library(ggplot2)
library(tidyverse)
library(ggcorrplot)
library(grid)
library(gridExtra)
library(caret)
library(mclust)
library(boot)
library(MLeval)

## LOADING DATA SET 
data <- read.csv("training.csv")

## Finding variables with high correlation (> 0.85)
## Note: Used feature selection using P-value in the end 


var_names = names(data)
num_vars = length(var_names)

for (i1 in 1:(num_vars-1))
{
  v1 = var_names[i1]
  for (i2 in (i1+1):num_vars)
  {
    v2 = var_names[i2]
    
    c = cor(data[,v1], data[,v2])
    if (abs(c) > 0.85)
    {
      print(paste(v1, v2, sep=' - '))
      print(c)
    }
  }
}

set.seed(1)
## SELECTING VARIABLES USING LOGISTIC REGRESSION 
## USING GML TO SELECT VARIABLES (Selection method 1) 

logistic_reg = glm(class ~ ., data=data)
pvals = coef(summary(logistic_reg))[,4]
pvals = pvals[2:length(pvals)]

## STORING VARIABLES WITH HIGH P-VALUES (FINAL-1)
vars_to_keep <- names(data)[pvals < .00001] 


## MULTINOMIAL CROSS VALIDATIONS WITH ENTIRE DATA SET (Selection method 2) 

## METRICS FOR EVALUATION
train_control <- trainControl(method="cv", number = 5, 
                              classProbs = TRUE, 
                              savePredictions = TRUE)



## CONVERTING CLASS TO A FACTOR 
data$class <- factor(data$class)
levels(data$class) <- c("NG", "OG", "TSG")

LRfit <- train(class~., 
               data = data, method = "multinom",
               preProc = c("center", "scale"),
               trControl = train_control)

## ESTIMATING P-VALUES 
z <- summary(LRfit)$coefficients/summary(LRfit)$standard.errors
p <- (1 - pnorm(abs(z), 0, 1)) * 2

##STORING VARIABLES WITH HIGH P-VALUES  (FINAL 2)
vars_to_keep2 <- c("BioGRID_log_degree", "Missense_Entropy", "VEST_score",
                   "Missense_Damaging_TO_Missense_Benign_Ratio", 
                   "Gene_body_hypermethylation_in_cancer", "CNA_amplification")  

## COMBINING OUR BEST VARIABLES 
model_1 <- c(vars_to_keep, vars_to_keep2)

variables <- model_1

data = data[,c(variables, "class")]
data$class <- factor(data$class)
levels(data$class) <- c("NG", "OG", "TSG")


## CREATING TRAINING DATA SET

#70% of data for train and 30% of data for test
train_size = floor(0.7 * nrow(data))

#get training indices
train_ind = sample(seq_len(nrow(data)), size = train_size)

data_train = data[train_ind, ]
data_test = data[-train_ind, ]

## VISUALIZING OUR VARIABLES - JITTER PLOTS
plots <- list(0)
box_plots <- list(0)
for (feat in variables)
{
  plots[[feat]] = ggplot(data, aes_string(feat, "class")) + 
    geom_jitter(width=0.05, height=0.1, size=0.4) + 
    theme_classic()
}

## VISUALIZING OUR VARIABLES - BOX PLOTS 

for (feat in variables)
{
  box_plots[[feat]] = ggplot(data, 
                             aes_string(x = "class", 
                                        feat, 
                                        fill = "class")) + 
    geom_boxplot(outlier.colour="grey", 
                 outlier.shape=19, 
                 outlier.size=1) + 
    scale_fill_manual(values=c("#D7D7D2", 
                               "#2D68C4", 
                               "#F2A900")) + 
    theme_classic()  +  theme(legend.position = "none")
}


loop_predictors <- variables
entire_table <- list(0)
best_pred <- list(0)
best_pred_CV <- list(0)

## CROSS VALIDATION FOR ALL COMBINATIONS OF VARIABLES 
## OUTPUT: 
## 1. BEST PREDICTORS FOR EACH n 
## 2. ACCURACY LEVELS 

set.seed(1)
for (k in 1:13) {
  pred <- k
  loop_pred <- combn(loop_predictors, pred)
  n <- (length(loop_pred)/pred)
  results_pred <- matrix(nrow = n, 
                         ncol = 3)
  colnames(results_pred) <- c("Index", "Naive", "Diff.Thres")
  
  for (i in 1:n) {
    results_pred[i,1] <- i
    data_loop <- data[c(loop_pred[,i], "class")]
    data_train_loop = data_loop[train_ind, ]
    data_test_loop = data_loop[-train_ind, ]
    
    logistic_reg_loop = nnet::multinom(class ~ ., data=data_train_loop)
    pred_logic_test <- predict(logistic_reg_loop, data_test_loop[, -(pred+1), drop = FALSE])
    
    results_pred[i,2] <- mean(pred_logic_test == data_test_loop$class)
    
    
    pp_raw <- predict(logistic_reg_loop, data_test_loop[, -(pred+1), drop = FALSE], "probs")
    pp <- pp_raw*100
    testing.set <- rep(0, length(pp[,1]))
    for(j in 1:length(testing.set)){
      if(pp[j,1] > 85 ){
        testing.set[j] <- 0 
      }else{
        if(pp[j,2] >  pp[j,3] | pp[j,2] > 40){
          testing.set[j] <- 1
        }else{
          if(pp[j,2] <  pp[j,3]){
            testing.set[j] <- 2
          }
        }
      }
    }
    testing.set <- as.factor(testing.set)
    levels(testing.set) <- c("NG", "OG", "TSG")
    
    results_pred[i,3] <- mean(testing.set == data_test_loop$class)
  }
  
  final <- as.data.frame(results_pred) %>% 
    arrange(desc(Naive))
  
  entire_table[[pred]] <- final
  
  best_pred[[pred]] <- c(loop_pred[,final[1,1]], final[1,2])
}

## BASED ON CV 
model_2 <- c("N_Splice", "Super_Enhancer_percentage", "H4K20me1_height",
             "BioGRID_log_degree", "Missense_Entropy", "VEST_score", 
             "Gene_body_hypermethylation_in_cancer", "CNA_amplification")

variables <- model_2
data = data[,c(variables, "class")]
data$class <- factor(data$class)
levels(data$class) <- c("NG", "OG", "TSG")

set.seed(1234)
train_size = floor(0.7 * nrow(data))
train_ind = sample(seq_len(nrow(data)), size = train_size)


data_train = data[train_ind, ]
data_test = data[-train_ind, ]

logistic_reg = nnet::multinom(class ~ ., data=data_train)
summary(logistic_reg)


pred_logic_test <- predict(logistic_reg, data_test[, -(length(variables) + 1)])

pp_raw <- predict(logistic_reg, data_test[,-(length(variables) + 1)], "probs")

pp <- pp_raw*100
testing.set <- rep(0, length(pp[,1]))


## SIMPLE VERSION 
for(i in 1:length(testing.set)){
  if(pp[i,1] > 85){
    testing.set[i] <- 0 
  }else{
    if(pp[i,2] >  pp[i,3]){
      testing.set[i] <- 1
    }else{
      if(pp[i,2] <  pp[i,3]){
        testing.set[i] <- 2
      }
    }
  }
}

incorrect_index <- which(pred_logic_test != data_test$class)
incorrect_probs <- pp[c(incorrect_index),]

testing.set.final <- as.factor(testing.set)
levels(testing.set.final) <- c("NG", "OG", "TSG")

mean(pred_logic_test == data_test$class)
mean(testing.set.final == data_test$class)

sum(pred_logic_test != testing.set.final)
sum(pred_logic_test != data_test$class)
sum(testing.set.final != data_test$class)

testing_incorrect_index <- which(testing.set.final != data_test$class)
testing_incorrect_probs <- pp[c(testing_incorrect_index),]

table(data_test$class[c(incorrect_index)])
table(data_test$class[c(testing_incorrect_index)])


testing.incorrect <- cbind(incorrect_probs, 
                           data.frame(
                             "pred" = pred_logic_test[c(incorrect_index)]), 
                           "actual" = data_test$class[c(incorrect_index)])


retesting.incorrect <- cbind(testing_incorrect_probs, 
                             data.frame(
                               "pred" = testing.set.final[c(testing_incorrect_index)]), 
                             "actual" = data_test$class[c(testing_incorrect_index)])
## CHECK YOUR DATA 
retesting.incorrect ##threshold 
testing.incorrect #without threshold

## FUNCTION TO EVALUATE OUR MODELS 
get_wca <- function(pred, true)
{
  #get max score
  max_score = sum(true == "NG")*1 + sum(true == "OG")*20 + sum(true=="TSG")*20
  
  #get achieved score
  score = sum((true == "NG")&(pred == "NG"))*1 + 
    sum((true == "OG")&(pred == "OG"))*20 + 
    sum((true == "TSG")&(pred == "TSG"))*20
  #get wca
  
  return (score/max_score)
}

get_wca(testing.set.final, data_test$class)

## NEW FINAL OUTPUT 
test <- read.csv("test.csv")
sample <- read.csv("sample.csv")

## CHOSEN PREDICTORS 
sample.prob <- predict(logistic_reg, test[,variables], "probs")

sample_pp <- sample.prob*100
testing.sample <- rep(0, length(sample_pp[,1]))

## CHOSEN THRESHOLD VALUES 
for(i in 1:length(testing.sample)){
  if(sample_pp[i,1] > 85){
    testing.sample[i] <- 0 
  }else{
    if(sample_pp[i,2] >  sample_pp[i,3] | sample_pp[i,2 > 40]){
      testing.sample[i] <- 1
    }else{
      if(sample_pp[i,2] <  sample_pp[i,3]){
        testing.sample[i] <- 2
      }
    }
  }
}

## CROSS CHECKING AND CONVERTING 

sample$class <- as.integer(testing.sample)
table(sample$class)

## FINAL DOCUMENT 
write.csv(sample,"cvlogistic.csv", row.names = FALSE)
