
# 01. Defining directory
getwd()
setwd("D:/Purdue/01Krannert/16 Industry Practicum/03 Data/IP") # Provide your directory here

# 02. Installing all packages
# a. Do not run if you already have these packages installed 
  # install.packages("tidyverse")
  # install.packages("forecast")
  # install.packages("tseries")
  # install.packages("cluster")
  # install.packages("boot")
  # install.packages("cowplot")
  # install.packages("lubridate")
  # install.packages("MLmetrics")
  # install.packages("fastDummies")
  # install.package s("dplyr")
  # install.packages("devtools")
  # install.packages("cluster")
  # install.packages("factoextra")
  # install.packages("fpc")
  # install.packages("clValid")
  # install.packages("caret")
  # devtools::install_github("RamiKrispin/TSstudio")

# b. Initializing libraries
# install.packages("vctrs")
# update.packages(c("vctrs"))
library(tidyverse)
library(forecast)
library(tseries)
library(cluster)
library(ggplot2)
library(boot)

library(cowplot)
library(lubridate)
library(TSstudio)
library(MLmetrics)
library(fastDummies)
library(dplyr)
library(cluster)
library(factoextra)
library(fpc)
library(clValid)
library(caret)

# 03. Reading raw data
demo<-read.csv("demographics.csv",header=TRUE)
market_share_and_failure_rate_data<-read.csv("market_share_and_failure_rate_data.csv",header=TRUE)
sales_history<-read.csv("sales_history.csv",header=TRUE)
vio_sector_id<-read.csv("vio_sector_id.csv",header=TRUE)
vio_store_number_no_aces<-read.csv("vio_store_number_no_aces.csv",header=TRUE)

# 04. Reading geocoded cities data
city_geoencode <- read.csv("uscities.csv",header=TRUE)

# 05. Selecting for only store 7848
Store7848 <- sales_history %>%
  filter(STORE_NUMBER == 7848 )

Store7848_aggr1<-Store7848 %>%
  group_by(STORE_NUMBER,MPOG_ID,FISCAL_YEAR,FISCAL_PERIOD) %>%
    summarize(sum_sales=sum(SUM.GROSS_SALES.),sum_qty=sum(SUM.QTY_SOLD.))

Store7848_aggr2<-Store7848_aggr1 %>%
  group_by(STORE_NUMBER,MPOG_ID) %>%
    summarise(mean_sales=mean(sum_sales),mean_qty=mean(sum_qty))

all_store_aggr1<-sales_history %>%
  group_by(MPOG_ID,FISCAL_YEAR,FISCAL_PERIOD) %>%
  summarize(sum_sales=sum(SUM.GROSS_SALES.),sum_qty=sum(SUM.QTY_SOLD.))

all_store_aggr2<-all_store_aggr1 %>%
  group_by(MPOG_ID) %>%
  summarize(mean_sales=mean(sum_sales),mean_qty=mean(sum_qty))


write.csv(Store7848_aggr2,"Store7848_aggr2.csv")
write.csv(all_store_aggr2,"all_store_aggr2.csv")









# 05. Check for any missing values
sapply(demo, function(x) sum(is.na(x)))
sapply(market_share_and_failure_rate_data, function(x) sum(is.na(x)))
sapply(sales_history, function(x) sum(is.na(x)))
sapply(vio_sector_id, function(x) sum(is.na(x)))
sapply(vio_store_number_no_aces, function(x) sum(is.na(x)))
# Findings: there is no missing values in all the tables except in sales history tabe where 4904 MPOG_ID 
# are missing

# 06. Preparing Cluster data 
# a. Converting store number to numeric
market_share_and_failure_rate_data$store.number<- as.numeric(market_share_and_failure_rate_data$store.number)

# b. Left join demographics data and market share data with demo data as left table
# Purpose for joining here is to get market share data along with demo data for stores
for_cluster_data <- left_join(demo,market_share_and_failure_rate_data, by=c("STORE_NUMBER" = "store.number"))
str(market_share_and_failure_rate_data)
# c. Checking for blanks and imputing with zero if found any
sapply(for_cluster_data, function(x) sum(is.na(x)))

#d. Converting type, dma, city and state from factor to character variable before imputation
for_cluster_data$type<-as.character(for_cluster_data$type)
for_cluster_data$dma<-as.character(for_cluster_data$dma)
for_cluster_data$city<-as.character(for_cluster_data$city)
for_cluster_data$state<-as.character(for_cluster_data$state)

# e. Imputing missing values with blanks
for_cluster_data[is.na(for_cluster_data)] <- 0

# 07. Preparing vehicle data
vehicle_count_sum<-vio_store_number_no_aces %>%
  group_by(STORE_NUMBER) %>%
  summarise(Vehicle_Count =sum(`UNADJUSTED_VEHICLE_COUNT`))

# 08. Preparing cluster data 2
# a. Left join for_cluster_data with vehicle data. Purpose of the join is to get vehicle count added to our
# pre clustering data
for_cluster_data2 <- left_join(for_cluster_data,vehicle_count_sum, by = c("STORE_NUMBER" = "STORE_NUMBER"))
# b. Checking for blanks
sapply(for_cluster_data2, function(x) sum(is.na(x)))


# 09. creating  a list for columns to be dropped 
drops <- c("index.x","index.y",'total.aap.cq.units', 'total.market.share','difm.market.share',
           'diy.aap.cq.units','difm.aap.cq.units','diy.market.share','POP_FEMALE','EDU_SOME_COLLEGE',
           'EDU_HIGH_SCHOOL','ESTABLISHMENTS')
drops2 <- c('state.x','City','type','dma','state.y','city','index.x','index.y')

# 10. Preparing cluster data 3
for_cluster_data3<- left_join(for_cluster_data2,city_geoencode,by=c("STORE_NUMBER" = "store.number"))

# 11. Creating dummy columns for cluster data
for_cluster_data4 <- fastDummies::dummy_cols(for_cluster_data3,select_columns=c('state.x','dma','type'))

# 12. Dropping unneccesary columns from pre clustering data
for_cluster_data4<-for_cluster_data4[ , !(names(for_cluster_data4) %in% drops)]
for_cluster_data4<-for_cluster_data4[ , !(names(for_cluster_data4) %in% drops2)]

# 13. Checking for nulls in pre clustering data
sapply(for_cluster_data4, function(x) sum(is.na(x)))
for_cluster_data4[is.na(for_cluster_data4)] <- 0

# 14. Trying multiple clustering techniques on our data
# a. K-Means clustering
# (i) Function for clustering
kmean_withinss <- function(k) {
  cluster <- kmeans(for_cluster_data4, k)
  return (cluster$tot.withinss)
}
# (ii) Number of max clusters(k) to test for
max_k <-20

# (iii) to create elbow plot we calcluate within sum of squares
wss <- sapply(2:max_k, kmean_withinss)
#View(wss)

# (iv) Getting wss with k number
elbow <-data.frame(2:max_k, wss)

# (v) Plotting the elbow plot
ggplot(elbow, aes(x = X2.max_k, y = wss)) +
  geom_point() +
  geom_line() +
  scale_x_continuous(breaks = seq(1, 20, by = 1))

# (vi) From k-means we get 7 clusters 
final <- kmeans(for_cluster_data4, 7, nstart =25)
# View(final)

# b. K-PAM Clustering method 
# (i) K-PAM clustering
kpam <- pam(x=for_cluster_data4,k=10,keep.diss=TRUE, keep.data=TRUE)
#kpam
# View(kpam)

# (ii) silhouette Plot for K-PAM
fviz_nbclust(for_cluster_data4, hcut, method="silhouette")

# (iii) Mapping clusters created back to store data 
kpamc <-cbind(for_cluster_data4, cluster = kpam$clustering)
head(kpamc)

# c. Bootstrap evaluation of clusters and all the methods ae tested with K value as 5,6,7,8,9,10,11,12
# (i) Initializing cluster number to be 10
kbest.p <- 10

# (ii) Removing store number 
for_cluster_data5 <- select(for_cluster_data4, -c('STORE_NUMBER'))
summary(for_cluster_data5)

# (iii) Clustering using bootstrapped method
cboot.clust <- clusterboot(for_cluster_data5,clustermethod = pamkCBI, multipleboot = TRUE,
                           B=100, 
                           bootmethod=c("boot","noise","subset"), 
                           k=kbest.p, seed=1234)

# (iv) Getting cluster groups
groups <-cboot.clust$result$partition
# print(groups)

# (v) Getting Jaccard coefficient
cboot.clust$bootmean
# 0.8832688 0.5599104 0.6734677 0.5677057 0.8584942 0.5614966 0.5756273 0.5709381 0.4949454 0.7037879

# (vi) Getting number of resolutions
cboot.clust$bootbrd
# 9 38 13 53  2 43 43 39 70 18

# d. K-PAM after getting accurate number of clusters from Bootstrap evaluation
# (i)
kpamd <- pam(x=for_cluster_data5,k=10, keep.diss=TRUE, keep.data=TRUE)
kpamd1 <- cbind(for_cluster_data5, cluster = kpamd$clustering)

# (ii) Mapping clusters back to store
store_cluster_kpam <- cbind(Store_Number=kpamd1$STORE_NUMBER ,Cluster = kpamd1$cluster)
store_cluster_kpam <- as.data.frame(store_cluster_kpam)

# (iii) Store distribution across clusters
table(store_cluster_kpam$Cluster)
# 1  2  3  4  5  6  7  8  9 10 
# 7 34 34 41 15 29 29 19 30 17

# e. K-Means after getting accurate number of clusters from Bootstrap evaluation
kbest.p_c <- 7
cboot.clustc <- clusterboot(for_cluster_data5,clustermethod = kmeansCBI, multipleboot = TRUE,
                            B=100, 
                            bootmethod=c("boot","noise","subset"), 
                            k=kbest.p_c, seed=1234)

# (ii) Getting Jaccard coefficient
cboot.clustc$bootmean
# 0.7236096 0.6529111 0.5038800 0.7481532 0.7372146 0.6426121 0.7204158

# (iii) Getting number of resolutions
cboot.clustc$bootbrd
# 11 24 65 21 16 39 14

# (iv) Getting all clusters
groups <-cboot.clustc$result$partition
print(groups)
head(cboot.clustc,3)

# (v) Store distribution across all clusters
table(groups)

# 1  2  3  4  5  6  7 
# 64 17  6 35 57 42 34

# e. Clustering using CLARA
# (i) Selecting the best number of clusters 
kbest.p=10
cboot.clust <- clusterboot(for_cluster_data5,clustermethod = claraCBI, multipleboot = TRUE,
                           B=100, 
                           bootmethod=c("boot","noise","subset"), 
                           k=kbest.p, seed=1234)

# (ii) Getting Jaccard coefficient
cboot.clust$bootmean
# 0.8832688 0.5599104 0.6734677 0.5677057 0.8584942 0.5614966 0.5756273 0.5709381 0.4949454 0.7037879

# (iii) Getting clusters
groups <-cboot.clust$result$partition
print(groups)
head(cboot.clust,3)

# (iv) Getting number of resolutions
cboot.clust$bootbrd
# 9 38 13 53  2 43 43 39 70 18

# (v) Store distribution across clusters
table(groups)
# 1  2  3  4  5  6  7  8  9 10 
# 7 34 34 41 15 29 29 19 30 17 

# f. Clustering using Hierarchical clusering
# (i) Selecting the accurate cluster numbers
kbest.p=8
cboot.clust <- clusterboot(for_cluster_data5,clustermethod = hclustCBI, multipleboot = TRUE,
                           B=100, method='average',
                           bootmethod=c("boot","noise","subset"), 
                           k=kbest.p, seed=1234)

# (ii) Getting Jaccard Coefficients
cboot.clust$bootmean
# 0.9391460 0.7779359 0.5057687 0.6101245 0.6100000 0.5359136 0.6100000 0.6101653

# (iii) Getting number of resolutions
cboot.clust$bootbrd
# 0 23 47 39 39 49 39 39

# (iv) Getting clusters
groups <-cboot.clust$result$partition
print(groups)
head(cboot.clust,3)

# (v) Store distribution across clusters
table(groups)
# 1   2   3   4   5   6   7   8 
# 238   3   9   1   1   1   1   1 

# g. Clustering using Spectral clustering
# Selecting the accurate number of clusters
kbest.p=6
cboot.clust <- clusterboot(for_cluster_data5,clustermethod = speccCBI, multipleboot = TRUE,
                           B=100, method='average',
                           bootmethod=c("boot","noise","subset"), 
                           k=kbest.p, seed=1234)


# (ii) Getting Jaccard Coefficient
cboot.clust$bootmean
# 0.6399686 0.7451469 0.2911162 0.7445016 0.7396550 0.6598062

# (iii) Getting number of resolutions
cboot.clust$bootbrd
# 27 14 90 14 12 28

# (iv) Getting clusters
groups <-cboot.clust$result$partition
print(groups)
head(cboot.clust,3)

# (v) Store distribution across clusters
table(groups)
# 1  2  3  4  5  6 
# 45 33 17 65 78 17 

# 15. Validation based on connectivity, stability, AD, Dunn 
for_cluster_data6 <- for_cluster_data5
rownames(for_cluster_data6) <- for_cluster_data5$STORE_NUMBER
cl <- clValid(for_cluster_data6,7:10, clMethods = c("hierarchical","pam","kmeans","clara"),validation = "internal")
summary(cl)
# Clustering Methods:
#   hierarchical pam kmeans clara 
# 
# Cluster sizes:
#   7 8 9 10 
# 
# Validation Measures:
#   7       8       9      10
# 
# hierarchical Connectivity  37.5639 47.1810 53.1710 56.1544
# Dunn           0.0649  0.0735  0.0906  0.0906
# Silhouette     0.4374  0.4276  0.4263  0.4247
# pam          Connectivity  62.1071 65.3960 73.4083 91.2524
# Dunn           0.0160  0.0217  0.0217  0.0149
# Silhouette     0.3951  0.4138  0.3979  0.3554
# kmeans       Connectivity  41.9155 50.1488 57.7635 59.0135
# Dunn           0.0441  0.0602  0.0602  0.0602
# Silhouette     0.4889  0.4580  0.4514  0.4479
# clara        Connectivity  58.2679 79.3615 69.3286 84.4111
# Dunn           0.0229  0.0173  0.0271  0.0390
# Silhouette     0.4470  0.3956  0.3879  0.3759
# 


# 16. Removing the 4 new stores opened in 2017
# (i) Store 7521.7755,7848 and 7910
for_cluster_data7<-for_cluster_data4[ !for_cluster_data4$STORE_NUMBER %in% c(7521,7755,7848,7910), ]
# (ii) Removing store number from clustering
for_cluster_data8 <- select(for_cluster_data7, -c('STORE_NUMBER'))
str(for_cluster_data8)
# (iii) Checking if there are any missing values in data
sapply(for_cluster_data8, function(x) sum(is.na(x)))

# (iv) Imputing missing value with zero
for_cluster_data8[is.na(for_cluster_data8)] <- 0

# (iii) Perform Clustering 
cboot.clust_r <- clusterboot(for_cluster_data8,clustermethod = pamkCBI, multipleboot = TRUE,
                             B=100, 
                             bootmethod=c("boot","noise","subset"), 
                             k=8, seed=1234)

groups <-cboot.clust_r$result$partition
print(groups)
head(cboot.clust_r,3)

# (iv) Getting Jaccard Coefficient
cboot.clust_r$bootmean
# 0.8628862 0.5957903 0.6432006 0.5748642 0.8602999 0.5669762 0.5743190 0.5856831 0.4835583 0.6985911

# (v) Getting number of resolutions
cboot.clust_r$bootbrd
# 9 32 28 47  7 42 47 34 69 23

# (vi) Performing K-PAM cluster
kpamd_r <- pam(x=for_cluster_data8,k=10, keep.diss=TRUE, keep.data=TRUE)
kpamd_r1 <- cbind(for_cluster_data8, cluster = kpamd_r$clustering)

# Mapping cluster number back to stores
store_cluster_final <- cbind(Store_Number=for_cluster_data7$STORE_NUMBER ,Cluster = kpamd_r1$cluster)
store_cluster_final<- as.data.frame(store_cluster_final)

write.csv(store_cluster_final,"test.csv")

# Store distribution across final established clusters
table(store_cluster_final$Cluster)
# 1  2  3  4  5  6  7  8  9 10 
# 7 36 27 20 15 35 23 22 37 29 

# 17. Renaming store name in final clustering dataset and geo encoded data
names(store_cluster_final)[1] <- "STORE_NUMBER"
names(city_geoencode)[1] <- "STORE_NUMBER"


# 18. Keeping STORE_NUMBER, AREA_LAND, AREA_WATER, POP_EST_CY, POP_DENSITY_CY, POP_MALE, AGE,
#TOTAL_VIO, EDU_TOTAL and UNEMPLOYMENT_RATE from demographics data
demo_filter<- demo[c(2,3,4,5,6,7,9,10,11,14,15,16,18)]

# 19. Keeping STORE_NUMBER, type, dma, total.failure.units, diy.failure.units, difm.failure.units
# from market share data
market <- market_share_and_failure_rate_data[c(2,3,4,8,11,14)]
names(market)[2]<-"STORE_NUMBER"

# 20. Keeping STORE_NUMBER, state, latitude, longitude from Geo endoded data
geo<-city_geoencode[c(1,3:5)]

# 21. Left Joining tables
# a. Cluster left join demo on Store Number
train_df <- left_join(store_cluster_final, demo_filter, on="STORE_NUMBER")

# b. Removing store 7650 which has data only in 2019
train_df<-train_df %>%
  filter(!STORE_NUMBER %in% 7650)

# b. train_df left join market on Store Number
train_df <- left_join(train_df, market, on="STORE_NUMBER")
# c. train_df left join geo on Store Number
train_df <- left_join(train_df, geo, on="STORE_NUMBER")

# 22. Subsetting the demographics dataset for stores opened in 2017
subset_df <- demo_filter[demo_filter$STORE_NUMBER %in% c(7521,7848,7755,7910), ]

# 23. Joining on STORE_NUMBER for test dataset
test_df <- left_join(subset_df, market, on="STORE_NUMBER")
test_df <- left_join(test_df, geo, on="STORE_NUMBER")

# 24. Removing STORE_NUMBER from train and test datasets
train_df_2 <- train_df[c(2:22)]
test_df_2 <- test_df[c(2:21)]



# 25. kNN classification for mapping new stores to clusters
# a. Setting seed so that results are reproducible
set.seed(3333)

# b. Converting the clusters into factors
train_df_2[["Cluster"]] = factor(train_df_2[["Cluster"]])

# c. Training the kNN model
trctrl <- trainControl(method = "repeatedcv", number = 10, repeats = 3)
knn_fit <- train(Cluster ~., data = train_df_2, method = "knn",
                 trControl=trctrl,
                 preProcess = c("center", "scale"),
                 tuneLength = 10)

# d. Mapping the stores in the test data to their clusters
test_pred <- predict(knn_fit, newdata = test_df_2)

test_pred
# Findings:
# 1.Store number is 7521 mapped to cluster 2
# 2.Store number is 7848 mapped to cluster 10
# 3.Store number is 7755 mapped to cluster 9
# 4.Store number is 7910 mapped to cluster 10

colnames(train_df_2)

# 06. Aggregating sales history removing the stores which are tagged as new stores
# Tagged new store numbers: 7910, 7848, 7755 and 7521
sales_history_wo_newstores<-sales_history %>%
  filter(!STORE_NUMBER %in% c(7910,7848,7755,7521))

# 07. Mapping cluster information with sales history table 
# a. Reading cluster data
# cluster_data <- read.csv("D:/Purdue/01Krannert/16 Industry Practicum/03 Data/IP/store_cluster_b (3).csv")

cluster_data<- store_cluster_final
str(store_cluster_final)
# store_cluster_final


names(cluster_data)[1] <- "STORE_NUMBER"

# b. Left join sales history with cluster data. Here sales history is the left table
cluster_sales_wo_newstores<-merge(x=sales_history_wo_newstores,y=cluster_data,by="STORE_NUMBER",all.x = TRUE)

# 08. Aggregating sales history for each cluster
# a. Summing sales data at Cluster, Store, Year and Period level 
cluster_store_grouped <- cluster_sales_wo_newstores %>%
  group_by(STORE_NUMBER, Cluster,FISCAL_YEAR, FISCAL_PERIOD) %>%
  summarise(sum_sales = sum(SUM.GROSS_SALES.))

# b. Averaging sales data across stores for each cluster 
Cluster_mean_sales <- cluster_store_grouped %>% 
  group_by(Cluster, FISCAL_YEAR,FISCAL_PERIOD) %>%
  summarise(mean_sales = mean(sum_sales))

# 09. Split sales data into Clusters
cluster1 <- Cluster_mean_sales %>%
  filter(Cluster== 1)

cluster2 <- Cluster_mean_sales %>%
  filter(Cluster== 2)

cluster3 <- Cluster_mean_sales %>%
  filter(Cluster== 3)

cluster4 <- Cluster_mean_sales %>%
  filter(Cluster== 4)

cluster5 <- Cluster_mean_sales %>%
  filter(Cluster== 5)

cluster6 <- Cluster_mean_sales %>%
  filter(Cluster== 6)

cluster7 <- Cluster_mean_sales %>%
  filter(Cluster== 7)

cluster8 <- Cluster_mean_sales %>%
  filter(Cluster== 8)

cluster9 <- Cluster_mean_sales %>%
  filter(Cluster== 9)

cluster10 <- Cluster_mean_sales %>%
  filter(Cluster== 10)

# 10. Converting transactional data into time series data
cluster1_ts <- ts(cluster1$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster2_ts <- ts(cluster2$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster3_ts <- ts(cluster3$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster4_ts <- ts(cluster4$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster5_ts <- ts(cluster5$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster6_ts <- ts(cluster6$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster7_ts <- ts(cluster7$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster8_ts <- ts(cluster8$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster9_ts <- ts(cluster9$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)
cluster10_ts <- ts(cluster10$mean_sales, start=c(2014,1), end=c(2019,13), frequency = 13)

# 11. Filtering out new store information from sales history data
# a. Store number 7910 is mapped to cluster 10
store7910 <- sales_history %>%   
  filter(STORE_NUMBER == 7910)

# b. Store number 7848 is mapped to cluster 10
store7848 <- sales_history %>%  
  filter(STORE_NUMBER == 7848)

# c. Store number 7755 is mapped to cluster 9
store7755 <- sales_history %>%  
  filter(STORE_NUMBER == 7755)

# d. Store number 7521 is mapped to cluster 2
store7521 <- sales_history %>% 
  filter(STORE_NUMBER == 7521)

# 12. Aggregating sales history data for new store data
store7521_grouped <- store7521 %>%
  group_by(STORE_NUMBER, FISCAL_YEAR, FISCAL_PERIOD) %>%
  summarise(sum_sales = sum(SUM.GROSS_SALES.))

store7910_grouped <- store7910 %>%
  group_by(STORE_NUMBER, FISCAL_YEAR, FISCAL_PERIOD) %>%
  summarise(sum_sales = sum(SUM.GROSS_SALES.))

store7848_grouped <- store7848 %>%
  group_by(STORE_NUMBER, FISCAL_YEAR, FISCAL_PERIOD) %>%
  summarise(sum_sales = sum(SUM.GROSS_SALES.))

store7755_grouped <- store7755 %>%
  group_by(STORE_NUMBER, FISCAL_YEAR, FISCAL_PERIOD) %>%
  summarise(sum_sales = sum(SUM.GROSS_SALES.))


# 13. Converting new stores sales to time series
store7910ts <- ts(store7910_grouped$sum_sales, start=c(2017,1), end=c(2019,13), frequency = 13)
store7848ts <- ts(store7848_grouped$sum_sales, start=c(2017,13), end=c(2019,13), frequency = 13)
store7755ts <- ts(store7755_grouped$sum_sales, start=c(2017,9), end=c(2019,13), frequency = 13)
store7521ts <- ts(store7521_grouped$sum_sales, start=c(2017,1), end=c(2019,13), frequency = 13)

# a. Plotting new store time series data and corresponding cluster mean sales
tsplot1 <- autoplot(cluster2_ts, series="Mean Cluster 2 Sales") +
  autolayer(store7521ts, series="Store 7848",colour=TRUE) +
  ylab("Plotting New store vs Cluster Mean") + guides(colour=guide_legend(title="Actual Sales"))
tsplot1

tsplot2 <- autoplot(cluster10_ts, series="Mean Cluster 10 Sales") +
  autolayer(store7848ts, series="Store 7755",colour=TRUE) + 
  ylab("Plotting New store vs Cluster Mean") + guides(colour=guide_legend(title="Actual Sales"))
tsplot2

tsplot3 <- autoplot(cluster9_ts, series="Mean Cluster 9 Sales") +
  autolayer(store7755ts, series="Store 7521",colour=TRUE) +
  ylab("Plotting New store vs Cluster Mean") + guides(colour=guide_legend(title="Actual Sales"))
tsplot3

tsplot4 <- autoplot(cluster10_ts, series="Mean Cluster 10 Sales") +
  autolayer(store7910ts, series="Store 7910",colour=TRUE) +
  ylab("Plotting New store vs Cluster Mean") + guides(colour=guide_legend(title="Actual Sales"))
tsplot4

# 14. Subsetting the mean sales of corresponding clusters to be used for forecasting for one year
# a. Change the end in the below code to filter and create time series
# (i) For Cluster 2
cluster2_filterts <- ts(cluster2$mean_sales, start=c(2014,1), end=c(2017,12), frequency = 13)
cluster_filterplt2<-plot.ts(cluster2_filterts)

# (ii) For Cluster 10
cluster10_filterts <- ts(cluster10$mean_sales, start=c(2014,1), end=c(2017,12), frequency = 13)
cluster_filterplt10<-plot.ts(cluster10_filterts)

# (iii) For Cluster 9
cluster9_filterts <- ts(cluster9$mean_sales, start=c(2014,1), end=c(2017,12), frequency = 13)
cluster_filterplt9<-plot.ts(cluster9_filterts)


# 15. Univariate time series forecasting
# a. ETS
# (i) For Cluster 2
etsfc_train2 <- cluster2_filterts %>% ets() %>% forecast(h=13)
# View(etsfc_train6)
etsfc_train2$method

# (ii) For Cluster 10
etsfc_train10 <- cluster10_filterts %>% ets() %>% forecast(h=13)
etsfc_train10$method

# (iii) For Cluster 9
etsfc_train9 <- cluster9_filterts %>% ets() %>% forecast(h=13)
etsfc_train9$method

# b. Bagged ETS
# (ii) For Cluster 2
etsmodel2<-baggedModel(cluster2_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster2_filterts, 10), fn = ets)
# View(etsmodel2)
# autoplot(etsmodel2$residuals)
bagged_ets_forecast2<-forecast(etsmodel2,h=13)

# (ii) For Cluster 10
etsmodel10<-baggedModel(cluster10_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster10_filterts, 10), fn = ets)
etsmodel10$method
bagged_ets_forecast10<-forecast(etsmodel10,h=13)

# (iii) For Cluster 9
etsmodel9<-baggedModel(cluster9_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster9_filterts, 10), fn = ets)
bagged_ets_forecast9<-forecast(etsmodel9,h=13)

View(etsmodel9)

# c. HW
# (ii) For Cluster 2
hwfc_train2 <- cluster2_filterts %>% hw() %>% forecast(h=13)
# (ii) For Cluster 10
hwfc_train10 <- cluster10_filterts %>% hw() %>% forecast(h=13)
# (iii) For Cluster 9
hwfc_train9 <- cluster9_filterts %>% hw() %>% forecast(h=13)

# d. Bagged HW
# (i) For Cluster 2
hwmodel2<-baggedModel(cluster2_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster2_filterts, 10), fn = hw)
bagged_hw_forecast2<-forecast(hwmodel2,h=13)
View(bagged_hw_forecast2)
# (ii) For Cluster 10
hwmodel10<-baggedModel(cluster10_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster10_filterts, 10), fn = hw)
bagged_hw_forecast10<-forecast(hwmodel10,h=13)
# (iii) For Cluster 9
hwmodel9<-baggedModel(cluster9_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster9_filterts, 10), fn = hw)
bagged_hw_forecast9<-forecast(hwmodel9,h=13)


# e. ARIMA
# (ii) For Cluster 2
arima_fit_2 <- auto.arima(cluster2_filterts)
summary(arima_fit_2)
arimafc_train2 <- forecast(arima_fit_2,  h=13)
# (ii) For Cluster 10
arima_fit_10 <- auto.arima(cluster10_filterts)
arimafc_train10 <- forecast(arima_fit_10,  h=13)
# (iii) For Cluster 9
arima_fit_9 <- auto.arima(cluster9_filterts)
arimafc_train9 <- forecast(arima_fit_9,  h=13)


# f. Bagged ARIMA
# (i) For Cluster 2
arimamodel2<-baggedModel(cluster2_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster2_filterts, 10), fn = auto.arima)
bagged_arima_forecast2<-forecast(arimamodel2,h=13)
# (ii) For Cluster 10
arimamodel10<-baggedModel(cluster10_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster10_filterts, 10), fn = auto.arima)
bagged_arima_forecast10<-forecast(arimamodel10,h=13)
# (iii) For Cluster 9
arimamodel9<-baggedModel(cluster9_filterts, bootstrapped_series = bld.mbb.bootstrap(cluster9_filterts, 10), fn = auto.arima)
bagged_arima_forecast9<-forecast(arimamodel9,h=13)


# e. Plot to visualize Actual, Prediction from ETS and Prediction from Bagged ETS
store7848ts_filtered <- ts(store7848_grouped$sum_sales, start=c(2017,13), end=c(2018,13), frequency = 13)
store7755ts_filtered <- ts(store7755_grouped$sum_sales, start=c(2017,13), end=c(2018,13), frequency = 13)
store7910ts_filtered <- ts(store7910_grouped$sum_sales, start=c(2017,13), end=c(2018,13), frequency = 13)
store7521ts_filtered <- ts(store7521_grouped$sum_sales, start=c(2017,13), end=c(2018,13), frequency = 13)

train_plot1<-autoplot(cluster2_filterts,series="Actual Mean Cluster 2 sales", xlab = "Time",ylab="Sales") +
  autolayer(hwfc_train2$mean, series="HW", PI=FALSE) +
  autolayer(bagged_hw_forecast2$mean, series="BaggedHW", PI=FALSE) +
  autolayer(etsfc_train2$mean, series="ETS", PI=FALSE) +
  autolayer(bagged_ets_forecast2$mean, series="BaggedETS", PI=FALSE) +
  autolayer(arimafc_train2$mean, series="ARIMA", PI=FALSE) +
  autolayer(bagged_arima_forecast2$mean, series="BaggedARIMA", PI=FALSE) +
  autolayer(store7521ts_filtered, series="Store 7521", PI=FALSE) +
  guides(colour=guide_legend(title="Forecasts"))
train_plot1

train_plot2<-autoplot(cluster10_filterts,series="Actual Mean Cluster 10 sales", xlab = "Time",ylab="Sales") +
  autolayer(hwfc_train10$mean, series="HW", PI=FALSE) +
  autolayer(bagged_hw_forecast10$mean, series="BaggedHW", PI=FALSE) +
  autolayer(etsfc_train10$mean, series="ETS", PI=FALSE) +
  autolayer(bagged_ets_forecast10$mean, series="BaggedETS", PI=FALSE) +
  autolayer(arimafc_train10$mean, series="ARIMA", PI=FALSE) +
  autolayer(bagged_arima_forecast10$mean, series="BaggedARIMA", PI=FALSE) +
  autolayer(store7848ts_filtered, series="Store 7848", PI=FALSE) +
  guides(colour=guide_legend(title="Forecasts"))
train_plot2

train_plot3<-autoplot(cluster9_filterts,series="Actual Mean Cluster 9 sales", xlab = "Time",ylab="Sales") +
  autolayer(hwfc_train9$mean, series="HW", PI=FALSE) +
  autolayer(bagged_hw_forecast9$mean, series="BaggedHW", PI=FALSE) +
  autolayer(etsfc_train9$mean, series="ETS", PI=FALSE) +
  autolayer(bagged_ets_forecast9$mean, series="BaggedETS", PI=FALSE) +
  autolayer(arimafc_train9$mean, series="ARIMA", PI=FALSE) +
  autolayer(bagged_arima_forecast9$mean, series="BaggedARIMA", PI=FALSE) +
  autolayer(store7755ts_filtered, series="Store 7755", PI=FALSE) +
  guides(colour=guide_legend(title="Forecasts"))
train_plot3

train_plot4<-autoplot(cluster10_filterts,series="Actual Mean Cluster 10 sales", xlab = "Time",ylab="Sales") +
  autolayer(hwfc_train10$mean, series="HW", PI=FALSE) +
  autolayer(bagged_hw_forecast10$mean, series="BaggedHW", PI=FALSE) +
  autolayer(etsfc_train10$mean, series="ETS", PI=FALSE) +
  autolayer(bagged_ets_forecast10$mean, series="BaggedETS", PI=FALSE) +
  autolayer(arimafc_train10$mean, series="ARIMA", PI=FALSE) +
  autolayer(bagged_arima_forecast10$mean, series="BaggedARIMA", PI=FALSE) +
  autolayer(store7910ts_filtered, series="Store 7910", PI=FALSE) +
  guides(colour=guide_legend(title="Forecasts"))
train_plot4

# 16. Getting predictions from the list
# a. Bagged HW
pred_bagged_hw2<-bagged_hw_forecast2$mean
pred_bagged_hw10<-bagged_hw_forecast10$mean
pred_bagged_hw9<-bagged_hw_forecast9$mean

# b. HW
pred_hw2<-hwfc_train2$mean
pred_hw10<-hwfc_train10$mean
pred_hw9<-hwfc_train9$mean

# c. ETS
pred_ETS2 <- etsfc_train2$mean
pred_ETS10 <- etsfc_train10$mean
pred_ETS9 <- etsfc_train9$mean

# d. Bagged ETS
pred_BAgged_ETS2 <- bagged_ets_forecast2$mean
pred_BAgged_ETS10 <- bagged_ets_forecast10$mean
pred_BAgged_ETS9 <- bagged_ets_forecast9$mean

# e. ARIMA
pred_ARIMA2 <- arimafc_train2$mean
pred_ARIMA10 <- arimafc_train10$mean
pred_ARIMA9 <- arimafc_train9$mean

# f. Bagged ARIMA
pred_BAgged_ARIMA2 <- bagged_arima_forecast2$mean
pred_BAgged_ARIMA10 <- bagged_arima_forecast10$mean
pred_BAgged_ARIMA9 <- bagged_arima_forecast9$mean

# 18. Calculating MAPE to gauge if Bootstarpping improved forecasting accuracy
# a. Mape between actual sales and HW
MAPE(pred_hw2,store7521ts_filtered)
# 0.09638198
MAPE(pred_hw10,store7848ts_filtered)
# 0.123986
MAPE(pred_hw9,store7755ts_filtered)
# 0.6140028
MAPE(pred_hw10,store7910ts_filtered)
# 1.118403

# b. Mape between actual sales and Bagged HW
MAPE(pred_bagged_hw2,store7521ts_filtered)
# 0.09515719
MAPE(pred_bagged_hw10,store7848ts_filtered)
# 0.1123775
MAPE(pred_bagged_hw9,store7755ts_filtered)
# 0.605154
MAPE(pred_bagged_hw10,store7910ts_filtered)
# 1.140016

# c. Mape between actual sales and ETS
MAPE(pred_ETS2,store7521ts_filtered)
# 0.09579986
MAPE(pred_ETS10,store7848ts_filtered)
# 0.08123552
MAPE(pred_ETS9,store7755ts_filtered)
# 0.7127018
MAPE(pred_ETS10,store7910ts_filtered)
# 1.240025

# d. Mape between actual sales and Bagged ETS
MAPE(pred_BAgged_ETS2,store7521ts_filtered)
# 0.09423202
MAPE(pred_BAgged_ETS10,store7848ts_filtered)
# 0.0866887
MAPE(pred_BAgged_ETS9,store7755ts_filtered)
# 0.6496336
MAPE(pred_BAgged_ETS10,store7910ts_filtered)
# 1.211732

# e. Mape between actual sales and ARIMA
MAPE(pred_ARIMA2 ,store7521ts_filtered)
# 0.08283728
MAPE(pred_ARIMA10,store7848ts_filtered)
# 0.09676286
MAPE(pred_ARIMA9,store7755ts_filtered)
# 0.5755712
MAPE(pred_ARIMA10,store7910ts_filtered)
# 1.144903

# Test Accuracy using ARIMA model
(1-MAPE(pred_ARIMA2 ,store7521ts_filtered))
# 0.9171627
(1-MAPE(pred_ARIMA10 ,store7848ts_filtered))
# 0.9032371
(1-MAPE(pred_ARIMA9,store7755ts_filtered))
# 0.4244288
(1-MAPE(pred_ARIMA10,store7910ts_filtered))
# -0.1449029

# f. Mape between actual sales and Bagged ARIMA
MAPE(pred_BAgged_ARIMA2 ,store7521ts_filtered)
# 0.08811881
MAPE(pred_BAgged_ARIMA10,store7848ts_filtered)
# 0.1012578
MAPE(pred_BAgged_ARIMA9,store7755ts_filtered)
# 0.5957064
MAPE(pred_BAgged_ARIMA10,store7910ts_filtered)
# 1.168916

# Test Accuracy using ARIMA model
(1-MAPE(pred_BAgged_ARIMA2 ,store7521ts_filtered))
# 0.9118812
(1-MAPE(pred_BAgged_ARIMA10 ,store7848ts_filtered))
# 0.8987422
(1-MAPE(pred_BAgged_ARIMA9,store7755ts_filtered))
# 0.4042936
(1-MAPE(pred_BAgged_ARIMA10,store7910ts_filtered))
# -0.1689159


# 38. Getting fitted from the list
# a. Bagged HW
fitted_bagged_hw2<-hwmodel2$fitted
fitted_bagged_hw10<-hwmodel10$fitted
fitted_bagged_hw9<-hwmodel9$fitted

# b. HW
fitted_hw2<-hwfc_train2$fitted
fitted_hw10<-hwfc_train10$fitted
fitted_hw9<-hwfc_train9$fitted

# c. ETS
fitted_ETS2 <- etsfc_train2$fitted
fitted_ETS10 <- etsfc_train10$fitted
fitted_ETS9 <- etsfc_train9$fitted

# d. Bagged ETS
fitted_BAgged_ETS2 <- etsmodel2$fitted
fitted_BAgged_ETS10 <- etsmodel10$fitted
fitted_BAgged_ETS9 <- etsmodel9$fitted

# e. ARIMA
fitted_ARIMA2 <- arimafc_train2$fitted
fitted_ARIMA10 <- arimafc_train10$fitted
fitted_ARIMA9 <- arimafc_train9$fitted

# d. Bagged ARIMA
fitted_BAgged_ARIMA2 <- arimamodel2$fitted
fitted_BAgged_ARIMA10 <- arimamodel10$fitted
fitted_BAgged_ARIMA9 <- arimamodel9$fitted

# 39. Calculating MAPE to gauge if Bootstarpping improved forecasting accuracy
# a. Mape between actual sales and HW
MAPE(fitted_hw2,cluster2_filterts)
# 0.02570388
MAPE(fitted_hw10,cluster10_filterts)
# 0.02695085
MAPE(fitted_hw9,cluster9_filterts)
# 0.02509273
# MAPE(pred_hw10,store7910ts_filtered)
# 1.118403

# b. Mape between actual sales and Bagged HW
MAPE(fitted_bagged_hw2,cluster2_filterts)
# 0.02481362
MAPE(fitted_bagged_hw10,cluster10_filterts)
# 0.02473783
MAPE(fitted_bagged_hw9,cluster9_filterts)
# 0.02315632
# MAPE(pred_bagged_hw10,store7910ts_filtered)
# 1.140016

# c. Mape between actual sales and ETS
MAPE(fitted_ETS2,cluster2_filterts)
# 0.02483283
MAPE(fitted_ETS10,cluster10_filterts)
# 0.02730269
MAPE(fitted_ETS9,cluster9_filterts)
# 0.02813689
# MAPE(pred_ETS10,store7910ts_filtered)
#1.240025

# d. Mape between actual sales and Bagged ETS
MAPE(fitted_BAgged_ETS2,cluster2_filterts)
# 0.02435725
MAPE(fitted_BAgged_ETS10,cluster10_filterts)
# 0.02497312
MAPE(fitted_BAgged_ETS9,cluster9_filterts)
# 0.02188671
# MAPE(pred_BAgged_ETS10,store7910ts_filtered)
# 1.211732

# e. Mape between actual sales and ARIMA
MAPE(fitted_ARIMA2,cluster2_filterts)
# 0.02081622
MAPE(fitted_ARIMA10,cluster10_filterts)
# 0.0259193
MAPE(fitted_ARIMA9,cluster9_filterts)
# 0.01983066
# MAPE(pred_ETS10,store7910ts_filtered)
#1.240025

(1-MAPE(fitted_ARIMA2,cluster2_filterts))
(1-MAPE(fitted_ARIMA10,cluster10_filterts))
(1-MAPE(fitted_ARIMA9,cluster9_filterts))

# f. Mape between actual sales and Bagged ARIMA
MAPE(fitted_BAgged_ARIMA2,cluster2_filterts)
# 0.02513928
MAPE(fitted_BAgged_ARIMA10,cluster10_filterts)
# 0.02589789
MAPE(fitted_BAgged_ARIMA9,cluster9_filterts)
# 0.02503046
# MAPE(pred_BAgged_ETS10,store7910ts_filtered)
# 1.211732

(1-MAPE(fitted_BAgged_ARIMA2,cluster2_filterts))
(1-MAPE(fitted_BAgged_ARIMA10,cluster10_filterts))
(1-MAPE(fitted_BAgged_ARIMA9,cluster9_filterts))




split_ts6 <- ts_split(ts.obj = cluster6_ts, sample.out = 13)
train6 <- split_ts6$train
test6 <- split_ts6$test


# 10. Bagging([B]ootstrap [Agg]regat[ing])
# a. ETS from actual for next 13 periods
etsfc_train6 <- train6 %>% ets() %>% forecast(h=13)
# b. ETS from mean of all simulated data for next 13 periods
etsmodel6<-baggedModel(train6, bootstrapped_series = bld.mbb.bootstrap(train6, 10), fn = ets)
bagged_ets_forecast6<-forecast(etsmodel6,h=13)
# b. HW from actual for next 13 periods
hwfc_train6 <- train6 %>% hw() %>% forecast(h=13)

# d. HW from mean of all simulated data for next 13 periods
hwmodel6<-baggedModel(train6, bootstrapped_series = bld.mbb.bootstrap(train6, 10), fn = hw)
bagged_hw_forecast6<-forecast(hwmodel6,h=13)
# e. ARIMA from actual for next 13 periods
arima_fit_6 <- auto.arima(train6)
arimafc_train6 <- forecast(arima_fit_6,  h=13)
# f. ARIMA from mean of all simulated data for next 13 periods
arimamodel6<-baggedModel(train6, bootstrapped_series = bld.mbb.bootstrap(train6, 10), fn = auto.arima)
bagged_arima_forecast6<-forecast(arimamodel6,h=13)


# c. Plot to visualize Actual, Peridtciosn from ETS and predictiosn from Bagged ETS
train_plot6<-autoplot(cluster6_ts,series="Actual Sales", PI=FALSE,size = 2) +
  autolayer(bagged_ets_forecast6, series="BaggedETS", PI=FALSE,size = 2) +
  autolayer(hwfc_train6, series="HW", PI=FALSE,size = 2) +
  autolayer(bagged_hw_forecast6, series="BaggedHW", PI=FALSE,size = 2) +
  autolayer(arimafc_train6, series="ARIMA", PI=FALSE,size=2) +
  autolayer(bagged_arima_forecast6, series="BaggedARIMA", PI=FALSE,size = 2) +
  autolayer(etsfc_train6, series="ETS", PI=FALSE,size = 2) + 
  ylab("Sales") + 
  theme(legend.text=element_text(size=40),title=element_text(size=50, face='bold'))+
  guides(colour=guide_legend(title="Forecasts for Cluster 6"))
train_plot6

write.csv(cluster6_ts,"cluster6_ts.csv")
write.csv(etsfc_train6,"etsfc_train6.csv")
write.csv(bagged_ets_forecast6,"bagged_ets_forecast6.csv")
write.csv(hwfc_train6,"hwfc_train6.csv")
write.csv(bagged_hw_forecast6,"bagged_hw_forecast6.csv")
write.csv(arimafc_train6,"arimafc_train6.csv")
write.csv(bagged_arima_forecast6,"bagged_arima_forecast6.csv")


png(file="mygraphic.png",width=2048,height=1536)
train_plot6
dev.off()