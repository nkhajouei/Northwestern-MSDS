# Unit 1 Project
# MSDS 411 Section 56
# Alan Kessler

library(reshape2)
library(ggplot2)
library(RColorBrewer)
library(mice)
library(car)
library(MASS)
library(dplyr)
library(caret)
library(party)
library(moments)

# Part 1: Data Exploration

# Load training and testing data
train <- read.csv("moneyball.csv")
test <- read.csv("moneyball_test.csv")

# High level summary of the target
summary(train$TARGET_WINS)

# Setting colors for plots
pal <- brewer.pal(3, "Set1")

# Visualize missing values in the data
MissingCount <- train %>%
  select(-INDEX) %>%
  mutate_all(is.na) %>%
  summarise_all(sum) %>%
  melt() %>%
  mutate(value = value / nrow(train)) %>%
  filter(value > 0) %>%
  rename("Missing_Fraction" = value)

ggplot(MissingCount, aes(x = variable, weight = Missing_Fraction)) +
  geom_bar(color = "black", fill = pal[1]) +
  xlab("Variable (Those with Missing Values)") +
  ylab("Missing Fraction") +
  ggtitle("Missing Values - Training") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

# Visualize the distribution of the model target
dataLine <- train %>%
  summarise(y75 = quantile(TARGET_WINS, 0.75),
            y25 = quantile(TARGET_WINS, 0.25),
            x75 = qnorm(0.75), x25 = qnorm(0.25)) %>%
  mutate(slope = (y75 - y25) / (x75 - x25), intercept = y75 - slope * x75)

# Check for normality in target
ggplot(train, aes(sample = TARGET_WINS)) +
  stat_qq(color = pal[1]) +
  geom_abline(data = dataLine, aes(slope = slope, intercept = intercept)) +
  xlab("Theoretical Quantiles") +
  ylab("Sample Quantiles") +
  ggtitle("Target Normal QQ-Plot") +
  theme(legend.position = "none")

# Statistical test for target normality
shapiro.test(train$TARGET_WINS)

# Merge training and testing for analyzing predictors
df1 <- train %>%
  select(-INDEX, -TARGET_WINS) %>%
  mutate(Data = "Training")

df2 <- test %>%
  select(-INDEX) %>%
  mutate(Data = "Testing")

df <- rbind(df1, df2) %>%
  melt(id.vars = "Data")

# High level summary of all predictors
summary(rbind(df1, df2))

# Box plots
ggplot(df, aes(x = variable, y = value, color = Data)) +
  xlab("Variable") +
  ylab("Count") +
  ggtitle("Box Plots for Predictor Variables") +
  geom_boxplot() +
  facet_wrap(~variable, scales = "free") +
  theme(strip.text.x = element_blank())

# Histograms
ggplot(df, aes(value, fill = Data)) +
  xlab("Variable Value") +
  ylab("Count") +
  ggtitle("Histograms for Predictor Variables") +
  geom_histogram(bins = 30, color = "black") +
  facet_wrap(~variable, scales = "free") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

# Training predictor correlation 
corr <- cor(train[complete.cases(train[, 2:ncol(train)]), 2:ncol(train)])
corr_melt <- melt(round(corr, 2))

ggplot(data = corr_melt, aes(x = Var1, y = Var2, fill = value)) +
  geom_tile() +
  geom_text(aes(Var2, Var1, label = value), color = "black", size = 2.75) +
  scale_fill_gradient2(low = pal[2], high = pal[1], mid = "white", midpoint = 0,
                       limit = c(-1, 1), space = "Lab", name = "Correlation") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        axis.text.y = element_text(size = 8),
        legend.text = element_text(size = 8),
        legend.title = element_text(size = 8),
        legend.key.size = unit(.75, "line")) +
  xlab("") +
  ylab("") +
  ggtitle("Correlation - Training Data")

# Visualize univariate relationships with the target
train_melt <- train[, 2:ncol(train)] %>%
  melt(., id.vars = "TARGET_WINS")

ggplot(train_melt, aes(x = value, y = TARGET_WINS)) +
  geom_point(fill = pal[1], color = "black", shape = 21, size = 1) +
  geom_smooth(method = lm) +
  facet_wrap(~variable, scales = "free") +
  ggtitle("Univariate Relationship with Target") +
  xlab("Predictor Variable Value") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

# Calculate skewness for each variable
train[, 2:ncol(train)] %>%
  summarise_all(skewness, na.rm = TRUE)

# Part 2: Data Preparation

# Drop pitching columns that appear incorrect
# The pitching statistics should have a different relationship with target
# Perfect correlation except for high values of pitching hits so remove those
# Remove cases where the team exceeds the record number of wins in a season 116
# Remove cases where the number of wins is fewer than the record
# Create identifier columns for missing data
# Create variable for singles to reduce correlation
# Create SB success variable to reduce correlation

train_prep <- train %>%
  filter(TEAM_PITCHING_H < 2000) %>%
  select(-TEAM_PITCHING_H,
         -TEAM_PITCHING_HR,
         -TEAM_PITCHING_BB,
         -TEAM_PITCHING_SO) %>%
  filter(TARGET_WINS <= 116,
         TARGET_WINS >= 20,
         TEAM_BATTING_H <= 1800) %>%
  mutate(TEAM_BATTING_SO_MISS = ifelse(is.na(TEAM_BATTING_SO), 1, 0),
         TEAM_BASERUN_SB_MISS = ifelse(is.na(TEAM_BASERUN_SB), 1, 0),
         TEAM_BASERUN_CS_MISS = ifelse(is.na(TEAM_BASERUN_CS), 1, 0),
         TEAM_BATTING_HBP_MISS = ifelse(is.na(TEAM_BATTING_HBP), 1, 0),
         TEAM_FIELDING_DP_MISS = ifelse(is.na(TEAM_FIELDING_DP), 1, 0),
         TEAM_BATTING_1B = TEAM_BATTING_H -
           TEAM_BATTING_2B -
           TEAM_BATTING_3B -
           TEAM_BATTING_HR)

# Apply same transformations to testing since it is also used in imputation
test_prep <- test %>%
  select(-TEAM_PITCHING_H,
         -TEAM_PITCHING_HR,
         -TEAM_PITCHING_BB,
         -TEAM_PITCHING_SO) %>%
  mutate(TEAM_BATTING_SO_MISS = ifelse(is.na(TEAM_BATTING_SO), 1, 0),
         TEAM_BASERUN_SB_MISS = ifelse(is.na(TEAM_BASERUN_SB), 1, 0),
         TEAM_BASERUN_CS_MISS = ifelse(is.na(TEAM_BASERUN_CS), 1, 0),
         TEAM_BATTING_HBP_MISS = ifelse(is.na(TEAM_BATTING_HBP), 1, 0),
         TEAM_FIELDING_DP_MISS = ifelse(is.na(TEAM_FIELDING_DP), 1, 0),
         TEAM_BATTING_1B = TEAM_BATTING_H -
           TEAM_BATTING_2B -
           TEAM_BATTING_3B -
           TEAM_BATTING_HR)

# Impute missing data

# Prepare data
train_impute_input <- train_prep %>%
  select(-TEAM_BATTING_SO_MISS, -TEAM_BASERUN_SB_MISS, -TEAM_BASERUN_CS_MISS,
         -TEAM_BATTING_HBP_MISS, -TEAM_FIELDING_DP_MISS,
         -TARGET_WINS, -INDEX) %>%
  mutate(Data = "train")

test_impute_input <- test_prep %>%
  select(-TEAM_BATTING_SO_MISS, -TEAM_BASERUN_SB_MISS, -TEAM_BASERUN_CS_MISS,
         -TEAM_BATTING_HBP_MISS, -TEAM_FIELDING_DP_MISS, -INDEX) %>%
  mutate(Data = "test")

# Combine training and testing for identical imputation
# The Mice package lacks a way to build an imputation and then apply it
#  to new data. The work-around here is to redo the imputation with all data.
impute_input <- rbind(train_impute_input, test_impute_input)

# Impute missing using decision trees
mice_df <- impute_input[1:(ncol(impute_input) - 1)]
impute_missing <- mice(mice_df,
                       m = 1, method = "cart", seed = 9798, maxit = 5)

# Save imputed data set
impute_output <- complete(impute_missing, 1)

# Add label of train vs. test
impute_output$Data <- impute_input$Data

# Visualize imputation
densityplot(impute_missing)

# Add back in the imputed data
# Remove the label for training vs. testing
# Add a gets on base variable
# Cap and transform variables
# Remove untransformed versions
# Remove observations with zero strikeouts as unintuitive
train_final <- train_prep %>%
  select(INDEX,
         TARGET_WINS,
         TEAM_BATTING_SO_MISS,
         TEAM_BASERUN_SB_MISS,
         TEAM_BASERUN_CS_MISS,
         TEAM_BATTING_HBP_MISS,
         TEAM_FIELDING_DP_MISS) %>%
  cbind(., impute_output[impute_output$Data == "train", ]) %>%
  select(-Data) %>%
  mutate(GETS_ON_BASE = TEAM_BATTING_H + TEAM_BATTING_BB + TEAM_BATTING_HBP,
         TEAM_BATTING_1B_CLOG = ifelse(TEAM_BATTING_1B >
                                         quantile(train_prep$TEAM_BATTING_1B,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BATTING_1B,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BATTING_1B + 1)),
         TEAM_BATTING_2B_C = ifelse(TEAM_BATTING_2B >
                                      quantile(train_prep$TEAM_BATTING_2B,
                                               probs = c(0.995),
                                               na.rm = TRUE),
                                    quantile(train_prep$TEAM_BATTING_2B,
                                             probs = c(0.995),
                                             na.rm = TRUE),
                                    TEAM_BATTING_2B),
         TEAM_BATTING_3B_CLOG = ifelse(TEAM_BATTING_3B >
                                         quantile(train_prep$TEAM_BATTING_3B,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BATTING_3B,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BATTING_3B + 1)),
         TEAM_BASERUN_SB_CLOG = ifelse(TEAM_BASERUN_SB >
                                         quantile(train_prep$TEAM_BASERUN_SB,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BASERUN_SB,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BASERUN_SB + 1)),
         TEAM_BASERUN_SB_S = TEAM_BASERUN_SB /
           (TEAM_BASERUN_SB + TEAM_BASERUN_CS),
         TEAM_BASERUN_SB_S_F = ifelse(0.3 > TEAM_BASERUN_SB_S,
                                      0.3,
                                      TEAM_BASERUN_SB_S),
         TEAM_FIELDING_E_CLOG = ifelse(TEAM_FIELDING_E >
                                         quantile(train_prep$TEAM_FIELDING_E,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_FIELDING_E,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_FIELDING_E + 1)),
         TEAM_FIELDING_DP_C = ifelse(TEAM_FIELDING_DP >
                                       quantile(train_prep$TEAM_FIELDING_DP,
                                                probs = c(0.995),
                                                na.rm = TRUE),
                                     quantile(train_prep$TEAM_FIELDING_DP,
                                              probs = c(0.995),
                                              na.rm = TRUE),
                                     TEAM_FIELDING_DP)) %>%
  filter(TEAM_BATTING_SO > 0) %>%
  select(-TEAM_BATTING_H, -TEAM_BATTING_1B, -TEAM_BATTING_2B, -TEAM_BATTING_3B,
         -TEAM_BASERUN_SB, -TEAM_BASERUN_CS, -TEAM_BASERUN_SB_S,
         -TEAM_FIELDING_E, -TEAM_FIELDING_DP, -TEAM_BATTING_HBP)

# Visualize transformation results
train_final_melt <- train_final[, 2:ncol(train_final)] %>%
  melt(., id.vars = "TARGET_WINS") %>%
  filter(!variable %in% c("TEAM_BATTING_SO_MISS",
                          "TEAM_BASERUN_SB_MISS",
                          "TEAM_BASERUN_CS_MISS",
                          "TEAM_BATTING_HBP_MISS",
                          "TEAM_FIELDING_DP_MISS"))

# Histograms for modified variables 
ggplot(train_final_melt, aes(value)) +
  xlab("Variable Value") +
  ylab("Count") +
  ggtitle("Histograms for Transformed Predictor Variables") +
  geom_histogram(bins = 30, color = "black", fill = pal[3]) +
  facet_wrap(~variable, scales = "free") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

# Training predictor correlation 
corr <- cor(train_final[, 2:ncol(train_final)])
corr_melt <- melt(round(corr, 2))

ggplot(data = corr_melt, aes(x = Var1, y = Var2, fill = value)) +
  geom_tile() +
  geom_text(aes(Var2, Var1, label = value), color = "black", size = 2.5) +
  scale_fill_gradient2(low = pal[2], high = pal[1], mid = "white", midpoint = 0,
                       limit = c(-1, 1), space = "Lab", name = "Correlation") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        axis.text.y = element_text(size = 8),
        legend.text = element_text(size = 8),
        legend.title = element_text(size = 8),
        legend.key.size = unit(.75, "line")) +
  xlab("") +
  ylab("") +
  ggtitle("Correlation - Training Data with Transformations")

# Relationship with target for modified variables
ggplot(train_final_melt, aes(x = value, y = TARGET_WINS)) +
  geom_point(fill = pal[1], color = "black", shape = 21, size = 1) +
  geom_smooth(method = lm) +
  facet_wrap(~variable, scales = "free") +
  ggtitle("Univariate Relationship with Target for Transformed Variables") +
  xlab("Predictor Variable Value") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

# Part 3: Build Models

# Split training data to observe how models fit on holdout data 
set.seed(6174)
trainIndex <- createDataPartition(train_final$TARGET_WINS, p = 0.7,
                                  list = FALSE,
                                  times = 1)

train_prelim <- train_final[ trainIndex, ]
train_validation <- train_final[-trainIndex, ]

# Validation mse function
val_mse <- function(model, log = FALSE) {
  if (log == TRUE) {
    predictions <- exp(predict(model, train_validation))
  } else {
    predictions <- predict(model, train_validation)
  }
  mse <- data.frame(predictions, train_validation$TARGET_WINS)
  names(mse) <- c("predictions", "TARGET_WINS")
  mse <- mse %>%
    mutate(sq_error = (TARGET_WINS - predictions) ^ 2) %>%
    summarise(mse_model1 = mean(sq_error))
  return(mse[1, 1])
}

# Model 1 - Homage to the movie where getting on base is all that matters
model1 <- lm(TARGET_WINS ~ GETS_ON_BASE, data = train_prelim)
summary(model1)

# Model 2 - Complete model
model2 <- lm(TARGET_WINS ~ TEAM_BATTING_HR +
               TEAM_BATTING_BB + TEAM_BATTING_SO +
               TEAM_BATTING_1B_CLOG + TEAM_BATTING_2B_C +
               TEAM_BATTING_3B_CLOG + TEAM_BASERUN_SB_CLOG +
               TEAM_BASERUN_SB_S_F + TEAM_FIELDING_E_CLOG +
               TEAM_FIELDING_DP_C + TEAM_BATTING_SO_MISS +
               TEAM_BASERUN_SB_MISS + TEAM_BASERUN_CS_MISS +
               TEAM_BATTING_HBP_MISS + TEAM_FIELDING_DP_MISS,
             data = train_prelim)

summary(model2)
vif(model2)

# Model 3 - Stepwise Regression
model3 <- stepAIC(model2, direction = "both", trace = 0)

summary(model3)
vif(model3)

# Model comparison
AIC(model1)
AIC(model2)
AIC(model3)
mean(model1$residuals ^ 2)
mean(model2$residuals ^ 2)
mean(model3$residuals ^ 2)
val_mse(model1)
val_mse(model2)
val_mse(model3)

# Bonus Model 4 - Model 3 Using GLM instead
# Results are the same as lm because default is gaussian family with
#  identity link function.
model4_spec <- lm(TARGET_WINS ~ TEAM_BATTING_HR +
                    TEAM_BATTING_BB + TEAM_BATTING_SO +
                    TEAM_BATTING_1B_CLOG + TEAM_BATTING_2B_C +
                    TEAM_BATTING_3B_CLOG + TEAM_BASERUN_SB_CLOG +
                    TEAM_BASERUN_SB_S_F + TEAM_FIELDING_E_CLOG +
                    TEAM_FIELDING_DP_C + TEAM_BATTING_SO_MISS +
                    TEAM_BASERUN_SB_MISS + TEAM_BASERUN_CS_MISS +
                    TEAM_BATTING_HBP_MISS + TEAM_FIELDING_DP_MISS,
                  data = train_prelim)
model4 <- stepAIC(model4_spec, direction = "both")

summary(model4)
AIC(model4)
mean(model4$residuals ^ 2)
val_mse(model4)

# Bonus use variables deemed most important by random forest model
set.seed(2141)
train_forest <- cforest(TARGET_WINS ~ TEAM_BATTING_HR +
                          TEAM_BATTING_BB + TEAM_BATTING_SO +
                          TEAM_BATTING_1B_CLOG + TEAM_BATTING_2B_C +
                          TEAM_BATTING_3B_CLOG + TEAM_BASERUN_SB_CLOG +
                          TEAM_BASERUN_SB_S_F + TEAM_FIELDING_E_CLOG +
                          TEAM_FIELDING_DP_C + TEAM_BATTING_SO_MISS +
                          TEAM_BASERUN_SB_MISS + TEAM_BASERUN_CS_MISS +
                          TEAM_BATTING_HBP_MISS + TEAM_FIELDING_DP_MISS,
                        data = train_prelim,
                        control = cforest_unbiased(mtry = 3, ntree = 100))
forest_imp <- varimp(train_forest, conditional = FALSE)
sort(forest_imp, decreasing = TRUE)

# Select the top predictors
vars <- paste("TARGET_WINS ~ ",
              paste(names(head(sort(forest_imp, decreasing = TRUE), 8)),
                    collapse = " + "))

model5 <- lm(vars, data = train_prelim)

summary(model5)
vif(model5)
mean(model5$residuals ^ 2)
val_mse(model5)

# Model 6 - Additional interaction terms on top of stepwise
model6 <- lm(TARGET_WINS ~ TEAM_BATTING_HR +
               TEAM_BATTING_BB +
               TEAM_BATTING_SO +
               TEAM_BATTING_1B_CLOG +
               TEAM_BATTING_3B_CLOG +
               TEAM_BASERUN_SB_CLOG +
               TEAM_FIELDING_E_CLOG +
               TEAM_FIELDING_DP_C +
               TEAM_BATTING_SO_MISS +
               TEAM_BASERUN_CS_MISS +
               TEAM_BATTING_HBP_MISS +
               TEAM_FIELDING_DP_MISS +
               TEAM_BATTING_HR:TEAM_BASERUN_SB_CLOG +
               TEAM_BATTING_SO:TEAM_FIELDING_E_CLOG,
             data = train_prelim)

summary(model6)
vif(model6)
AIC(model6)
mean(model6$residuals ^ 2)
val_mse(model6)

# Relationship with target for interactions
train_inter <- train_final %>%
  mutate(HR_SB = TEAM_BATTING_HR * TEAM_BASERUN_SB_CLOG,
         SO_E = TEAM_BATTING_SO * TEAM_FIELDING_E_CLOG)

ggplot(train_inter, aes(x = HR_SB, y = TARGET_WINS)) +
  geom_point(fill = pal[1], color = "black", shape = 21, size = 1) +
  geom_smooth(method = lm) +
  ggtitle("Univariate Relationship with Target") +
  xlab("TEAM_BATTING_HR * TEAM_BASERUN_SB_CLOG") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

ggplot(train_inter, aes(x = SO_E, y = TARGET_WINS)) +
  geom_point(fill = pal[1], color = "black", shape = 21, size = 1) +
  geom_smooth(method = lm) +
  ggtitle("Univariate Relationship with Target") +
  xlab("TEAM_BATTING_SO * TEAM_FIELDING_E_CLOG") +
  theme(strip.text.x = element_text(size = 7),
        axis.text.x = element_text(size = 6),
        axis.text.y = element_text(size = 6))

# Fit final model (model 6) to the entire training data
# Mix of performance and parsimony considerations
model_final <- lm(TARGET_WINS ~ TEAM_BATTING_HR +
                    TEAM_BATTING_BB +
                    TEAM_BATTING_SO +
                    TEAM_BATTING_1B_CLOG +
                    TEAM_BATTING_3B_CLOG +
                    TEAM_BASERUN_SB_CLOG +
                    TEAM_FIELDING_E_CLOG +
                    TEAM_FIELDING_DP_C +
                    TEAM_BATTING_SO_MISS +
                    TEAM_BASERUN_CS_MISS +
                    TEAM_BATTING_HBP_MISS +
                    TEAM_FIELDING_DP_MISS +
                    TEAM_BATTING_HR:TEAM_BASERUN_SB_CLOG +
                    TEAM_BATTING_SO:TEAM_FIELDING_E_CLOG,
                  data = train_final)
summary(model_final)
# Print coefficients to use in scoring
model_final$coefficients

# Compare coefficients between model6 and model_final as a check
model_coef <- data.frame(model_final$coefficients)
model_coef$model6 <- model6$coefficients

# Diagnoistic Plots
par(mfrow = c(2, 2))
plot(model_final)

# Part 4: Stand Alone Scoring Program

library(mice)
library(dplyr)

# Load training and testing data
train <- read.csv("moneyball.csv")
test <- read.csv("moneyball_test.csv")

# Missing Value Imputation
# The imputation uses both training and testing data so both must be processed
train_prep <- train %>%
  filter(TEAM_PITCHING_H < 2000) %>%
  select(-TEAM_PITCHING_H,
         -TEAM_PITCHING_HR,
         -TEAM_PITCHING_BB,
         -TEAM_PITCHING_SO) %>%
  filter(TARGET_WINS <= 116,
         TARGET_WINS >= 20,
         TEAM_BATTING_H <= 1800) %>%
  mutate(TEAM_BATTING_SO_MISS = ifelse(is.na(TEAM_BATTING_SO), 1, 0),
         TEAM_BASERUN_SB_MISS = ifelse(is.na(TEAM_BASERUN_SB), 1, 0),
         TEAM_BASERUN_CS_MISS = ifelse(is.na(TEAM_BASERUN_CS), 1, 0),
         TEAM_BATTING_HBP_MISS = ifelse(is.na(TEAM_BATTING_HBP), 1, 0),
         TEAM_FIELDING_DP_MISS = ifelse(is.na(TEAM_FIELDING_DP), 1, 0),
         TEAM_BATTING_1B = TEAM_BATTING_H -
           TEAM_BATTING_2B -
           TEAM_BATTING_3B -
           TEAM_BATTING_HR,
         TEAM_BASERUN_SB_S = TEAM_BASERUN_SB /
           (TEAM_BASERUN_SB + TEAM_BASERUN_CS))

# Apply same transformations to testing since it is also used in imputation
test_prep <- test %>%
  select(-TEAM_PITCHING_H,
         -TEAM_PITCHING_HR,
         -TEAM_PITCHING_BB,
         -TEAM_PITCHING_SO) %>%
  mutate(TEAM_BATTING_SO_MISS = ifelse(is.na(TEAM_BATTING_SO), 1, 0),
         TEAM_BASERUN_SB_MISS = ifelse(is.na(TEAM_BASERUN_SB), 1, 0),
         TEAM_BASERUN_CS_MISS = ifelse(is.na(TEAM_BASERUN_CS), 1, 0),
         TEAM_BATTING_HBP_MISS = ifelse(is.na(TEAM_BATTING_HBP), 1, 0),
         TEAM_FIELDING_DP_MISS = ifelse(is.na(TEAM_FIELDING_DP), 1, 0),
         TEAM_BATTING_1B = TEAM_BATTING_H -
           TEAM_BATTING_2B -
           TEAM_BATTING_3B -
           TEAM_BATTING_HR,
         TEAM_BASERUN_SB_S = TEAM_BASERUN_SB /
           (TEAM_BASERUN_SB + TEAM_BASERUN_CS))

# Prepare data
train_impute_input <- train_prep %>%
  select(-TEAM_BATTING_SO_MISS, -TEAM_BASERUN_SB_MISS, -TEAM_BASERUN_CS_MISS,
         -TEAM_BATTING_HBP_MISS, -TEAM_FIELDING_DP_MISS,
         -TARGET_WINS, -INDEX) %>%
  mutate(Data = "train")

test_impute_input <- test_prep %>%
  select(-TEAM_BATTING_SO_MISS, -TEAM_BASERUN_SB_MISS, -TEAM_BASERUN_CS_MISS,
         -TEAM_BATTING_HBP_MISS, -TEAM_FIELDING_DP_MISS, -INDEX) %>%
  mutate(Data = "test")

# Combine training and testing for identical imputation
impute_input <- rbind(train_impute_input, test_impute_input)

# Impute missing using decision trees
mice_df <- impute_input[1:(ncol(impute_input) - 1)]
impute_missing <- mice(mice_df,
                       m = 1, method = "cart", seed = 9798, maxit = 5)

# Save imputed data set
impute_output <- complete(impute_missing, 1)

# Add label of train vs. test
impute_output$Data <- impute_input$Data

# Feature Creation
test_final <- test_prep %>%
  select(INDEX,
         TEAM_BATTING_SO_MISS,
         TEAM_BASERUN_SB_MISS,
         TEAM_BASERUN_CS_MISS,
         TEAM_BATTING_HBP_MISS,
         TEAM_FIELDING_DP_MISS) %>%
  cbind(., impute_output[impute_output$Data == "test", ]) %>%
  select(-Data) %>%
  mutate(GETS_ON_BASE = TEAM_BATTING_H + TEAM_BATTING_BB + TEAM_BATTING_HBP,
         TEAM_BATTING_1B_CLOG = ifelse(TEAM_BATTING_1B >
                                         quantile(train_prep$TEAM_BATTING_1B,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BATTING_1B,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BATTING_1B + 1)),
         TEAM_BATTING_2B_C = ifelse(TEAM_BATTING_2B >
                                      quantile(train_prep$TEAM_BATTING_2B,
                                               probs = c(0.995),
                                               na.rm = TRUE),
                                    quantile(train_prep$TEAM_BATTING_2B,
                                             probs = c(0.995),
                                             na.rm = TRUE),
                                    TEAM_BATTING_2B),
         TEAM_BATTING_3B_CLOG = ifelse(TEAM_BATTING_3B >
                                         quantile(train_prep$TEAM_BATTING_3B,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BATTING_3B,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BATTING_3B + 1)),
         TEAM_BASERUN_SB_CLOG = ifelse(TEAM_BASERUN_SB >
                                         quantile(train_prep$TEAM_BASERUN_SB,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_BASERUN_SB,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_BASERUN_SB + 1)),
         TEAM_BASERUN_SB_S_F = ifelse(0.3 > TEAM_BASERUN_SB_S,
                                      0.3,
                                      TEAM_BASERUN_SB_S),
         TEAM_FIELDING_E_CLOG = ifelse(TEAM_FIELDING_E >
                                         quantile(train_prep$TEAM_FIELDING_E,
                                                  probs = c(0.995),
                                                  na.rm = TRUE),
                                       log(quantile(train_prep$TEAM_FIELDING_E,
                                                    probs = c(0.995),
                                                    na.rm = TRUE) + 1),
                                       log(TEAM_FIELDING_E + 1)),
         TEAM_FIELDING_DP_C = ifelse(TEAM_FIELDING_DP >
                                       quantile(train_prep$TEAM_FIELDING_DP,
                                                probs = c(0.995),
                                                na.rm = TRUE),
                                     quantile(train_prep$TEAM_FIELDING_DP,
                                              probs = c(0.995),
                                              na.rm = TRUE),
                                     TEAM_FIELDING_DP)) %>%
  select(-TEAM_BATTING_H, -TEAM_BATTING_1B, -TEAM_BATTING_2B, -TEAM_BATTING_3B,
         -TEAM_BASERUN_SB, -TEAM_BASERUN_CS, -TEAM_BASERUN_SB_S,
         -TEAM_FIELDING_E, -TEAM_FIELDING_DP, -TEAM_BATTING_HBP)

# Score (assignment asks for hard-coded coefficients and save output
# Some very low scores need flooring as they are outliers
scores <- test_final %>%
  mutate(P_TARGET_WINS = round(-103.27174679 +
                                 0.51132601 * TEAM_BATTING_HR +
                                 0.03345651 * TEAM_BATTING_BB -
                                 0.15437078 * TEAM_BATTING_SO +
                                 43.99152477  * TEAM_BATTING_1B_CLOG +
                                 9.38310884 * TEAM_BATTING_3B_CLOG +
                                 16.01157601 * TEAM_BASERUN_SB_CLOG -
                                 46.23717921 * TEAM_FIELDING_E_CLOG -
                                 0.11190441 * TEAM_FIELDING_DP_C +
                                 3.84390695 * TEAM_BATTING_SO_MISS +
                                 4.99687746 * TEAM_BASERUN_CS_MISS +
                                 2.91181024 * TEAM_BATTING_HBP_MISS +
                                 5.37261185 * TEAM_FIELDING_DP_MISS -
                                 0.08766125 * TEAM_BATTING_HR *
                                 TEAM_BASERUN_SB_CLOG +
                                 0.02718167  * TEAM_BATTING_SO *
                                 TEAM_FIELDING_E_CLOG,
                               2),
         P_TARGET_WINS = ifelse(P_TARGET_WINS < 10, 10, P_TARGET_WINS)) %>%
  select(INDEX, P_TARGET_WINS)

# Save output
write.csv(scores, "Kessler_test_scores.csv", row.names = FALSE)
