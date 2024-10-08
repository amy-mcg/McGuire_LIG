### Code used to download and analyse pollen data from the Neotoma Paleoecology Database spanning the Last Interglacial in NW Europe for publication in McGuire et al. (in prep).
### Amy McGuire
### School of Earth and Environment, University of Leeds
### September 2023

# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------

library(neotoma2)
library(textclean)
library(tidyverse)
library(ggplot2)
library(reshape2)
library(ggpubr)
library(factoextra)
library(gridExtra)
library(raster)
library(elevatr)
library(sf)
 

# -------------------------------------------------------------------------------------------------

# Download pollen data for NW Europe from the Neotoma database (this is large and time consuming - a file downloaded October 2023 is provided)

# NWE <- list(bbox = c(-20, 44, 20, 60))
# NWE_data <- get_datasets(loc = NWE$bbox, datasettype = "pollen", all_data = TRUE)
# NWE_pollen <- NWE_data %>% get_downloads(all_data = TRUE)
# NWE_pollen <-  samples(NWE_pollen) %>% 
#   group_by("age")
# saveRDS(NWE_pollen, "/Data/NWE_pollen_Oct23")

NWE_pollen <- readRDS("/Data/NWE_pollen_Oct23")

# Read in the pollen zone data file

NWE_pollen_zones <- read.csv("/Data/PAZs.csv")
subset <- as.numeric(NWE_pollen_zones$Neotoma_ID)

NWE_Eemian <- subset(NWE_pollen, datasetid %in% NWE_pollen_zones$Neotoma_ID)

# -------------------------------------------------------------------------------------------------
# Code to format the data, and to assign pollen zones to sites where pollen zonation schemes have been developed

NWE_Eemian_pollen <- NWE_Eemian %>% 
  ungroup %>%
  dplyr::filter(ecologicalgroup %in% c("TRSH")) %>%
  dplyr::filter(elementtype == "pollen") %>% 
  select("sitename", "depth", "datasetid", "sampleid", "variablename", "value") %>%
  group_by(sampleid) %>%
  mutate(pollencount = sum(value, na.rm = TRUE)) %>%
  group_by(variablename) %>% 
  mutate(prop = value / pollencount) %>% 
  ungroup %>%
  pivot_wider(id_cols = c(sampleid, sitename, depth, datasetid),
              names_from = variablename,
              values_from = prop,
              values_fill = 0) %>%
  mutate(Pinus = Pinus + `Pinus subg. Strobus`) %>%
  mutate(Carpinus = Carpinus + `Carpinus (triporate)`) %>%
  select("sitename", "datasetid",  "depth", "Betula", "Pinus", "Ulmus", "Quercus", "Corylus", "Carpinus", "Picea", "Abies")

NWE_Eemian_pollen_zoned <- NWE_Eemian_pollen %>%
  group_split(datasetid)

NWE_pollen_zones[is.na(NWE_pollen_zones)] <- 0
NWE_pollen_zones_cm <- NWE_pollen_zones
NWE_pollen_zones_cm[,3:18] <- as.matrix(NWE_pollen_zones_cm[,3:18])*100

assign.pol.zones <- function(x){
  site <- as.numeric(x[1,2])  # Check if this indexing is appropriate for 'site'
  call.line <- NWE_pollen_zones_cm[NWE_pollen_zones_cm$Neotoma_ID == site, ]
  
  poll.zones <- character(length = nrow(x))  # Initialize an empty character vector of appropriate length
  for (i in 1:nrow(x)) {
    row <- x[i,]
    poll.zone <- ""  # Initialize the variable outside the loop
    if (row$depth <= call.line$EW && row$depth >= call.line$EW.1) {
      poll.zone <- "EW"
    } else if (row$depth <= call.line$E6 && row$depth >= call.line$E6.1) {
      poll.zone <- "E6"
    } else if (row$depth <= call.line$E5 && row$depth >= call.line$E5.1) {
      poll.zone <- "E5"
    } else if (row$depth <= call.line$E4 && row$depth >= call.line$E4.1) {
      poll.zone <- "E4"
    } else if (row$depth <= call.line$E3 && row$depth >= call.line$E3.1) {
      poll.zone <- "E3"
    } else if (row$depth <= call.line$E2 && row$depth >= call.line$E2.1) {
      poll.zone <- "E2"
    } else if (row$depth <= call.line$E1 && row$depth >= call.line$E1.1) {
      poll.zone <- "E1"
    } else if (row$depth <= call.line$LS && row$depth >= call.line$LS.1) {
      poll.zone <- "LS"
    } else {
      poll.zone <- NA
    }
    poll.zones[i] <- poll.zone
  }
  
  x$poll_zones <- poll.zones  # Add a new column to the input data frame
  return(x)  # Return the vector of assigned poll zones
}

NWE_Eemian_pollen_zoned <- lapply(NWE_Eemian_pollen_zoned, assign.pol.zones)

NWE_Eemian_pollen_zoned <- do.call(rbind.data.frame, NWE_Eemian_pollen_zoned)


# -------------------------------------------------------------------------------------------------
# Code to plot the LIG pollen data for each individual site by depth

NWE_Eemian_pollen_sites <- NWE_Eemian_pollen %>%
  group_split(sitename)

NWE_Eemian_pollen_sites <- lapply(NWE_Eemian_pollen_sites, select, "sitename", "depth", "Betula", "Pinus", "Ulmus", "Quercus", "Corylus", "Carpinus", "Picea", "Abies")

NWE_Eemian_pollen_sites <- lapply(NWE_Eemian_pollen_sites, melt, id = c("depth", "sitename"), measure.vars=c("Betula", "Pinus", "Ulmus", "Quercus", "Corylus", "Carpinus", "Picea", "Abies"), variable_name = taxa)

plotdata <- function(x) {
  ggplot(data = x, aes(x = depth, y = value, fill = variable)) + 
    geom_area(position = 'stack') +
    labs(title = unique(x$sitename)) 
}

do.call(ggarrange,c(lapply(NWE_Eemian_pollen_sites, plotdata), ncol = 1, common.legend = T, legend = "bottom"))

# -------------------------------------------------------------------------------------------------
# Code to undertake principal component analysis (PCA) of the LIG pollen data, grouped by site and by zone

df <- data.matrix(NWE_Eemian_pollen_zoned[4:11])
df[is.na(df)] <- 0
pca_res <- princomp(df)

pca_res_ind <- get_pca_ind(pca_res)
pca_res_ind <- as.data.frame(pca_res_ind$coord)

NWE_Eemian_pollen_zoned_PCA <- as.data.frame(NWE_Eemian_pollen_zoned$sitename)
NWE_Eemian_pollen_zoned_PCA$sitename <- str_extract(NWE_Eemian_pollen_zoned$sitename, '\\w*')
NWE_Eemian_pollen_zoned_PCA$poll_zones <- NWE_Eemian_pollen_zoned$poll_zones
NWE_Eemian_pollen_zoned_PCA$PCA1 <- pca_res_ind$Dim.1
NWE_Eemian_pollen_zoned_PCA$PCA2 <- pca_res_ind$Dim.2

fviz_pca_biplot(pca_res, repel=TRUE, pointshape=21)

NWE_Eemian_pollen_zoned_PCA <- NWE_Eemian_pollen_zoned_PCA %>% drop_na(poll_zones)

ggplot(NWE_Eemian_pollen_zoned_PCA, aes(PCA1, PCA2)) +
  geom_point(aes(color = poll_zones, shape = sitename)) +
  scale_shape_manual(values=c(1,2,3,4,5,6,21,22,23,24,25))


# -------------------------------------------------------------------------------------------------
## Code to produce maps of the LIG sites wihtin the Neotoma Database, along with the modern shoreline and past ice margins after Batchelor et al., 2020.

NWE_Eemian_pollen_zoned <- 
  NWE_Eemian_pollen_zoned %>% 
  filter(!is.na(poll_zones))

p1 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Betula, fill = poll_zones)) + 
    geom_boxplot(outlier.shape = NA) + 
    geom_jitter(width = 0.2) + 
    theme(legend.position="top")
p2 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Pinus, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p3 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Ulmus, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p4 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Quercus, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p5 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Corylus, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p6 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Carpinus, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p7 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Picea, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")
p8 <- ggplot(NWE_Eemian_pollen_zoned, aes(x = poll_zones, y = Abies, fill = poll_zones)) + 
  geom_boxplot(outlier.shape = NA) + 
  geom_jitter(width = 0.2) + 
  theme(legend.position="top")

grid.arrange(p1, p2, p3, p4, p5, p6, p7, p8, ncol=4)

# Generate a data frame of lat/long coordinates covering NW Europe
NWE.df <- data.frame(x=seq(from=-20, to=20, length.out=10), 
                     y=seq(from=44, to=60, length.out=10))

# Assign a colour scale!
over.col <- colorRampPalette(c("white", "grey"))

# Get elevation data using elevatr package
prj_dd <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
elev <- get_elev_raster(NWE.df, prj = prj_dd, z = 4, clip = "bbox")

# Import ice sheet margins from Batchelor et al. (2020), available online at: https://doi.org/10.17605/OSF.IO/7JEN3
ice_margin_MIS6 <- shapefile("/Data/Batchelor2020/MIS6_best_estimate.shx")
ice_margin_MIS6 <- spTransform(ice_margin_MIS6, CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))
ice_margin_MIS6 = st_as_sf(ice_margin_MIS6)
ice_margin_MIS6 = st_crop(ice_margin_MIS6, xmin=-20, xmax=20, ymin=40, ymax=60)

ice_margin_MIS5c <- shapefile("/Data/Batchelor2020/MIS5c_best_estimate.shx")
ice_margin_MIS5c <- spTransform(ice_margin_MIS5c, CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))
ice_margin_MIS5c = st_as_sf(ice_margin_MIS5c)
ice_margin_MIS5c = st_crop(ice_margin_MIS5c, xmin=-20, xmax=20, ymin=40, ymax=60)

ice_margin_MIS5a <- shapefile("/Data/Batchelor2020/MIS5a_best_estimate.shx")
ice_margin_MIS5a <- spTransform(ice_margin_MIS5a, CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))
ice_margin_MIS5a = st_as_sf(ice_margin_MIS5a)
ice_margin_MIS5a = st_crop(ice_margin_MIS5a, xmin=-20, xmax=20, ymin=40, ymax=60)

ice_margin_MIS4 <- shapefile("/Data/Batchelor2020/MIS4_best_estimate.shx")
ice_margin_MIS4 <- spTransform(ice_margin_MIS4, CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))
ice_margin_MIS4 = st_as_sf(ice_margin_MIS4)
ice_margin_MIS4 = st_crop(ice_margin_MIS4, xmin=-20, xmax=20, ymin=40, ymax=60)

ice_margin_LGM <- shapefile("/Data/Batchelor2020/LGM_best_estimate.shx")
ice_margin_LGM <- spTransform(ice_margin_LGM, CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"))
ice_margin_LGM = st_as_sf(ice_margin_LGM)
ice_margin_LGM = st_crop(ice_margin_LGM, xmin=-20, xmax=20, ymin=40, ymax=60)

# Import modern day shorline data from Natural Earth, available online at: https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-coastline/
shoreline <- shapefile("/Data/ne_50m_coastline.shx")
shoreline = st_as_sf(shoreline)
shoreline_NWE = st_crop(shoreline, xmin=-20, xmax=20, ymin=40, ymax=60)

NWE_Eemian <- NWE_pollen %>%
  filter(str_detect(description, 'Eemian'))
NWE_Eemian <- unique(NWE_Eemian[c("sitename","lat", "long")])

NWE_Saalian <- NWE_pollen %>%
  filter(str_detect(description, 'Saalian'))
NWE_Saalian <- unique(NWE_Eemian[c("sitename","lat", "long")])

NWE_MIS6 <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 130000, maxage = 191000, all_data = TRUE)
NWE_MIS6 <- as.data.frame(NWE_MIS6)

NWE_MIS5e <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 109000, maxage = 130000, all_data = TRUE)
NWE_MIS5e <- as.data.frame(NWE_MIS5e)

NWE_MIS5c <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 87000, maxage = 109000, all_data = TRUE)
NWE_MIS5c <- as.data.frame(NWE_MIS5c)

NWE_MIS5a <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 71000, maxage = 87000, all_data = TRUE)
NWE_MIS5a <- as.data.frame(NWE_MIS5a)

NWE_MIS4 <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 57000, maxage = 71000, all_data = TRUE)
NWE_MIS4 <- as.data.frame(NWE_MIS4)

NWE_LGM <- get_sites(loc = NWE$bbox, datasettype = "pollen", minage = 29000, maxage = 14000, all_data = TRUE)
NWE_LGM <- as.data.frame(NWE_LGM)

par(mfrow=c(3,2))

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
plot(ice_margin_MIS6, add = TRUE, col = scales::alpha("#FFFFFF", 0.5))
points(NWE_MIS6$long, NWE_MIS6$lat, pch=16, col="#69C1D7")
points(NWE_Saalian$long, NWE_Saalian$lat, pch=16, col="#86972E")

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
points(NWE_MIS5e$long, NWE_MIS5e$lat, pch=16, col="#69C1D7")
points(NWE_Eemian$long, NWE_Eemian$lat, pch=16, col="#86972E")

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
plot(ice_margin_MIS5c, add = TRUE, col = scales::alpha("#FFFFFF", 0.5))
points(NWE_MIS5c$long, NWE_MIS5c$lat, pch=16, col="#69C1D7")

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
plot(ice_margin_MIS5a, add = TRUE, col = scales::alpha("#FFFFFF", 0.5))
points(NWE_MIS5a$long, NWE_MIS5a$lat, pch=16, col="#69C1D7")

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
plot(ice_margin_MIS4, col = scales::alpha("#FFFFFF", 0.5), add = TRUE)
points(NWE_MIS4$long, NWE_MIS4$lat, pch=16, col="#69C1D7")

plot(elev, col=over.col(100))
plot(shoreline_NWE, col = "white", add = TRUE)
plot(ice_margin_LGM, add = TRUE, col = scales::alpha("#FFFFFF", 0.5))
points(NWE_LGM$long, NWE_LGM$lat, pch=16, col="#69C1D7")


