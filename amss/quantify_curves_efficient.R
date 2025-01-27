
options(warn=-1)

list.of.packages <- c("tidyr", "plyr", "Rsamtools", "padr", "GenomicRanges", "ggplot2", "DescTools", "PCAtools", "gridExtra")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
#if(length(new.packages)) install.packages(new.packages)

suppressMessages(library(tidyr))
suppressMessages(library(plyr))
suppressMessages(library(Rsamtools))
#suppressMessages(library(padr))
suppressMessages(library(GenomicRanges))
suppressMessages(library(ggplot2))
suppressMessages(library(DescTools))
suppressMessages(library(PCAtools))
suppressMessages(library(gridExtra))
#suppressMessages(library(foreach))
#suppressMessages(library(doParallel))

options(warn=-1)

library(getopt)

opt <- NULL
# options to parse
spec <- matrix(c('chr',                   'c', 2, "character",   # chromosome
                 'start',                  's', 2, "character",   # start of region
                 'end',                    't', 2, "character",   # end of region
                 'out',                     'o', 1, "character",   # output dir
                 'sampleanno',              'a', 1, "character",   # sample annotation file
                 'pseudocount',              'p', 1, "numeric",    # 
                 'numrandomizations',       'n', 1, "numeric",      # number of randomiztions
                 'regfile',                 'r', 2, "character",      # file with regions
                 'debug',                   'd', 2, "logical",      # debug modus
                 'confirmRun2EndFile',      'e', 1, "character"
), ncol=4, byrow=T)

# parse the parameters
opt <- getopt(spec)


num_randomize_iters <- as.numeric(as.character(opt$numrandomizations))
shift_zeroline <- "median"
pseudocount <- as.numeric(as.character(opt$pseudocount))


#collect replicates, aggregate/normalize and compute c1-c2 and visa versa
preprocess <- function(s, e, chrom, dir) {
  dflist <- list()
  files <- list.files(path=paste0(dir, "/counts/"), pattern=".counts")
  for (rep in files) { #collect counts of replicates
    c <- read.csv(paste0(dir, "/counts/", rep), sep="\t", header=FALSE)
    colnames(c) <- c("start", "count")
    repname <- strsplit(rep, "\\.")[[1]][1]
    print(repname)
    dflist[[repname]] <- c
  }
  c1 <- dflist[names(dflist)%in%conds1] #divide reps to conditions
  c2 <- dflist[names(dflist)%in%conds2]
  cond1 <- Reduce(function(df1, df2) merge(df1, df2, by=c("start"), all=TRUE), c1) #aggregate reps
  cond2 <- Reduce(function(df1, df2) merge(df1, df2, by=c("start"), all=TRUE), c2)

  cond1[,2:ncol(cond1)] <- apply(cond1[,2:ncol(cond1)], 2, function(x) {
    x <- as.numeric(x)
    x[is.na(x)] <- 0
    total_sum <- sum(x)
    if (total_sum==0) { #ganzer vector nur 0, nix zu normalisieren
      return(x)
    } else {
      x <- (x/total_sum)*100
      return(x)
    }
  }) #normalize
  cond2[,2:ncol(cond2)] <- apply(cond2[,2:ncol(cond2)], 2, function(x) {
    x <- as.numeric(x)
    x[is.na(x)] <- 0
    total_sum <- sum(x)
    if (total_sum==0) { #ganzer vector nur 0, nix zu normalisieren
      return(x)
    } else {
      x <- (x/total_sum)*100
      return(x)
    }
  })
  
  cond1$meanCount <- apply(cond1[,2:ncol(cond1)], 1, mean) #mean per cond
  cond2$meanCount <- apply(cond2[,2:ncol(cond2)], 1, mean)
  cond1 <- cond1[,c(1,ncol(cond1))] 
  cond2 <- cond2[,c(1,ncol(cond2))]
  
  df <- merge(cond1, cond2, by="start")
  colnames(df) <- c("start", paste0(condname1, "_mean"), paste0(condname2, "_mean"))
  df$subtract <- df[,paste0(condname1, "_mean")] - df[,paste0(condname2, "_mean")] #c1-c2
  df$subtract <-  df$subtract - pseudocount/length(df$subtract)
  df$subtract2 <- df[,paste0(condname2, "_mean")] - df[,paste0(condname1, "_mean")] #c2-c1
  df$subtract2 <-  df$subtract2 - pseudocount/length(df$subtract2)
  df$chr <- chrom
  df <- df[,c(6,1,2,3,4,5)]
  write.table(df, paste0(dir, "normalized_aggregated_counts.tsv"), sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
  return(df)
}

#compute MSS
amss <- function(scores) {
  k <- 1
  total <- 0
  # Allocating arrays of size n
  I_s <- rep(0, length(scores))
  I_e <- rep(0, length(scores))
  L <- rep(0, length(scores))
  R <- rep(0, length(scores))
  Lidx <- rep(0, length(scores))
  for (i in 1:(length(scores))) {
    s <- scores[i]
    total <- total + s
    if (s > 0) {
      # store I[k] by (start,end) indices of scores
      I_s[k] <- i
      I_e[k] <- i
      Lidx[k] <- i
      L[k] <- total - s
      R[k] <- total
      while (TRUE) {
        maxj = NA
        for (j in(k:1)) {
          if (L[j] < L[k]) {
            maxj <- j
            break
          }
        }
        if (!is.na(maxj) && R[maxj] < R[k]) {
          I_s[maxj] <- Lidx[maxj]
          I_e[maxj] <- i
          R[maxj] <- total
          k <- maxj
        } else {
          k <- k + 1
          break
        }
      }
    }
  }
  # Getting maximal subsequences using stored indices
  init <- list(c(NA, NA))
  v <- c()
  v <- c(v, init)
  if (length(I_s) > 0 && length(I_e) > 0) {
    for (l in 1:k) {
      if (I_s[l]==0 && I_e[l]==0) { #beginning values, nothing found
        next
      } else {
        vec3 <- list(range(I_s[l] : I_e[l]))  #get start and end pos of MSS
      }
      v <- c(v, vec3)
    }
  } else {
    print("no MSS found")
    v <- c(v, list(c(NA, NA)))
  }
  return(v)
}

#comverts MSS to the start/end dataframe
amss2df <- function(res, df, c) {
  intervals <- c()
  for (v in res) {
    if (is.na(v[1]) || is.na(v[2])) {
      next
    }
    if (v[1]==v[2]) {  #can not compute AUC if AMSS only one position
      auc2 <- NA
    } else { #computes area under curve
      auc2 <- AUC(df[v,2], df[v,c], method="trapezoid", absolutearea=TRUE) #from DescTools, neg areas are summed
    }
    s <- sum(df[v[1]:v[2],c])
    intervals <- rbind(intervals, c(df[v,2], s, auc2))
  }
  intervals <- as.data.frame(intervals)
  colnames(intervals) <- c("start_seq_idx", "end_seq_idx", "sum_height", "AUC")
  intervals$len <- intervals$end_seq_idx-intervals$start_seq_idx
  return(intervals)
}

#collect MSS dataframes for both conditions
AMSSintervals <- function(df, type, dir, onlyMax, curvedifferences) {
  if (type=="median") {
    zeroline_c1 <- median(df[,paste0(condname1, "_mean")])
    zeroline_c2 <- median(df[,paste0(condname2, "_mean")])
  } else {
    zeroline_c1 <- mean(df[,paste0(condname1, "_mean")])
    zeroline_c2 <- mean(df[,paste0(condname2, "_mean")])
  }
  if (!curvedifferences) {
    df$subtract <- df$subtract - zeroline_c1
    df$subtract2 <- df$subtract2 - zeroline_c2
  }
  
  #computes MSS and formats as dataframe
  c1_c2 <- amss(df$subtract)
  s <- which(colnames(df)=="subtract")
  intervals <- amss2df(c1_c2, df, s)
  c2_c1 <- amss(df$subtract2)
  s <- which(colnames(df)=="subtract2")
  intervals2 <- amss2df(c2_c1, df, s)
  if (onlyMax) { #randomization needed only to filter above maximum
    return(c(max(intervals$sum_height), max(intervals2$sum_height)))
  } else {
    dt <- list()
    dt[[condname1]] <- intervals
    dt[[condname2]] <- intervals2
    return(dt)
  }
}

#randomize column of subtracted counts
randomize <- function(df) {
  collected <- df[,c(1,2,3)] #chr,start,mean
  for (i in 1:num_randomize_iters) {
    tmp <- sample(df[,4])
    collected <- cbind(collected, tmp)
  }
  return(as.data.frame(collected))
}

#filters MSS by longest randomized MSS
filterAMSSlengths <- function(list, vec) {
  c1c2_list <- list[[1]]
  c1c2_list <- subset(c1c2_list, c1c2_list$sum_height > vec[1])
  c2c1_list <- list[[2]]
  c2c1_list <- subset(c2c1_list, c2c1_list$sum_height > vec[2])
  t <- list(c1c2_list, c2c1_list)
  return(t)
}

#clean up MSS, retain only major ones. smaller contained are depleted
printFilteredAMSStogether <- function(list, dir) {
  c1_c2 <- list[[1]]
  c2_c1 <- list[[2]]
  c1_c2_filtered <- c()
  c2_c1_filtered <- c()
  c2_c1_del <- c()
  c1_c2_del <- c()
  for (line in 1:nrow(c1_c2)) { #defining MSS contained in opposite dir and delete
    tmp <- subset(c2_c1, c2_c1$start_seq_idx >= c1_c2$start_seq_idx[line] & 
                    c2_c1$start_seq_idx <= c1_c2$end_seq_idx[line])
    if (nrow(tmp)==0) {
      c1_c2_filtered <- rbind(c1_c2_filtered, c1_c2[line,])
    }
    else {
      tmp_h <- subset(tmp, tmp$sum_height>c1_c2$sum_height[line])
      tmp_l <- subset(tmp, tmp$sum_height<c1_c2$sum_height[line])
      if (nrow(tmp_h)==0) {
        c1_c2_filtered <- rbind(c1_c2_filtered, c1_c2[line,])
      }
      c2_c1_del <- rbind(c2_c1_del, tmp_l)
    }
  }
  c2_c1 <- subset(c2_c1, !(c2_c1$start_seq_idx %in% c2_c1_del$start_seq_idx))
  for (line in 1:nrow(c2_c1)) { #defining MSS contained in opposite dir and delete
    tmp <- subset(c1_c2, c1_c2$start_seq_idx >= c2_c1$start_seq_idx[line] & 
                    c1_c2$start_seq_idx <= c2_c1$end_seq_idx[line])
    if (nrow(tmp)==0) {
      c2_c1_filtered <- rbind(c2_c1_filtered, c2_c1[line,])
    }
    else {
      tmp_h <- subset(tmp, tmp$sum_height>c2_c1$sum_height[line])
      tmp_l <- subset(tmp, tmp$sum_height<c2_c1$sum_height[line])
      if (nrow(tmp_h)==0) {
        c2_c1_filtered <- rbind(c2_c1_filtered, c2_c1[line,])
      }
      c1_c2_del <- rbind(c1_c2_del, tmp_l)
    }
  }
  c1_c2_filtered <- subset(c1_c2_filtered, !(c1_c2_filtered$start_seq_idx %in% c1_c2_del$start_seq_idx))
  return(list(c1_c2_filtered, c2_c1_filtered))
}

#plots originally and filtered MSS
plotting <- function(list, list2, df) {
  df2 <- reshape2::melt(df[,c(1,2,3,4)], id.vars=c(1,2), variable.name="cond")
  
  plots <- list()
  
  #counts distrib
  p1 <- ggplot(df2, aes(start, value, col=cond, alpha=0.2)) + geom_line() + xlab("read start") +
    ylab("normed read counts") + 
    scale_color_manual(labels=c(condname1, condname2), values=c("lawngreen", "blue")) + 
    geom_smooth(aes(col=cond))
  plots[[length(plots)+1]] <- p1
  
  #counts distrib
  p2 <- ggplot(df2, aes(start, value, fill=cond)) + geom_col(width=5) + xlab("read start") +
    ylab("normed read counts") + 
    scale_fill_manual(labels=c(condname1, condname2), values=c("lawngreen", "blue")) +
    ylim(0,1)
  plots[[length(plots)+1]] <- p2
  
  #counts distrib subtracted
  p3 <- ggplot(df, aes(start,subtract)) + geom_line(aes(col=ifelse(subtract>=0, "red", "blue"))) + 
    ggtitle(paste0(condname1, " - ", condname2)) + 
    xlab("read start") + 
    ylab("count difference") + scale_color_identity() + 
    theme(legend.position="none")
  plots[[length(plots)+1]] <- p3
  
  #MSS c1-c2
  if (nrow(list[[1]]>0)) {
    p6 <- ggplot(list[[1]], aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      ggtitle(paste0(condname1, " - ", condname2))
    plots[[length(plots)+1]] <- p6
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  #MSS c2-c1
  if (nrow(list[[2]]>0)) {
    p7 <- ggplot(list[[2]], aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      ggtitle(paste0(condname2, " - ", condname1))
    plots[[length(plots)+1]] <- p7
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  #MSS combined
  tx <- list[[1]]
  if (nrow(tx)>0) {
    tx$type <- paste0(condname1, "-", condname2)
  }
  ty <- list[[2]]
  if (nrow(ty)>0) {
    ty$type <- paste0(condname2, "-", condname1)
  }
  if (nrow(tx)>0 && nrow(ty)>0) {
    t <- rbind(tx, ty)
  } else if (nrow(tx)>0 && nrow(ty)==0) {
    t <- tx
  } else if (nrow(ty)>0 && nrow(tx)==0) {
    t <- ty
  } else {
    t <- NA
  }
  
  if (!is.na(t)) {
    p8 <- ggplot(t, aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height, col=type)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      xlab("AMSS") + ylab("sum(normed counts)")
    plots[[length(plots)+1]] <- p8
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  if (nrow(list2[[1]])>0) {
    p6 <- ggplot(list2[[1]], aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      ggtitle(paste0(condname1, " - ", condname2))
    plots[[length(plots)+1]] <- p6
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  if (nrow(list2[[2]])>0) {
    p7 <- ggplot(list2[[2]], aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      ggtitle(paste0(condname2, " - ", condname1))
    plots[[length(plots)+1]] <- p7
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  
  tx <- list2[[1]]
  if (nrow(tx)>0) {
    tx$type <- paste0(condname1, "-", condname2)
  }
  ty <- list2[[2]]
  if (nrow(ty)>0) {
    ty$type <- paste0(condname2, "-", condname1)
  }
  if (nrow(tx)>0 && nrow(ty)>0) {
    t <- rbind(tx, ty)
  } else if (nrow(tx)>0 && nrow(ty)==0) {
    t <- tx
  } else if (nrow(ty)>0 && nrow(tx)==0) {
    t <- ty
  } else {
    t <- NA
  }
  
  #MSS combined filtered
  if (!is.na(t)) {
    p8 <- ggplot(t, aes(start_seq_idx+((end_seq_idx-start_seq_idx)/2), y=sum_height, col=type)) + 
      geom_pointrange(aes(xmin=start_seq_idx, xmax=end_seq_idx)) + 
      xlab("AMSS") + ylab("sum(normed counts)")
    plots[[length(plots)+1]] <- p8
  } else {
    plots[[length(plots)+1]] <- ggplot()
  }
  
  return(plots)
}


#calling all commands for a region
processWindow <- function(c, s, e) {
  w <- paste0(c, "-", s, "-", e)
  print(paste0("processing window: ", w))
  dir <- paste0(p, w, "/")
  if (!dir.exists(dir)) {
    dir.create(dir)
  }
  
  starttime2 <- Sys.time()
  df <- preprocess(s, e, c, dir)
  print(paste0("TIME aggregate ", (Sys.time()-starttime2)))
  
  starttime3 <- Sys.time()
  list <- AMSSintervals(df, shift_zeroline, dir, FALSE, TRUE)
  print(paste0("TIME AMSS ", (Sys.time()-starttime3)))
  
  starttime4 <- Sys.time()
  df_c1_c2_randomized <- randomize(df[,c(1,2,3,5)]) #sind immer chr,start,mean,subtract
  df_c2_c1_randomized <- randomize(df[,c(1,2,4,6)])
  print(paste0("TIME randomize ", (Sys.time()-starttime4)))
  
  starttime5 <- Sys.time()
  vector_max_scores <- c()
  df_randomized2 <- merge(df_c1_c2_randomized[,c(1,2,3)], df_c2_c1_randomized[,c(1,2,3)], by=c("chr", "start"))
  for (i in 4:(3+num_randomize_iters)) { #loop over num randomizations
    df_randomized <- merge(df_randomized2, df_c1_c2_randomized[,c(2,i)], by="start")
    df_randomized <- merge(df_randomized, df_c2_c1_randomized[,c(2,i)], by="start")
    colnames(df_randomized)[5:6] <- c("subtract", "subtract2")
    df_randomized <- df_randomized[,c(2,1,3,4,5,6)] #got table with randomized columns
    maxamssscores <- AMSSintervals(df_randomized, shift_zeroline, dir, TRUE, TRUE)
    vector_max_scores <- c(vector_max_scores, maxamssscores) #collect max. lengths of randomized MSS
  }
  subtractmax <- max(vector_max_scores[c(TRUE, FALSE)])
  subtract2max <- max(vector_max_scores[c(FALSE, TRUE)])
  vector_max_scores <- c(subtractmax, subtract2max)
  print(paste0("TIME randomized AMSS ", (Sys.time()-starttime5)))
  
  starttime6 <- Sys.time()
  list_randomized <- filterAMSSlengths(list, vector_max_scores)
  print(paste0("TIME filter AMSS ", (Sys.time()-starttime6), "  with max random scores: ", 
          paste(vector_max_scores, collapse=", "), " | left: ", 
          paste(c(nrow(list_randomized[[1]]), nrow(list_randomized[[2]])), collapse=", ")))
  
  list_randomized <- printFilteredAMSStogether(list_randomized)
  write.table(list_randomized[1], paste0(dir, condname1, "_", condname2, "_final_amss.tsv"), sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
  write.table(list_randomized[2], paste0(dir, condname2, "_", condname1, "_final_amss.tsv"), sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
  
  
  if (length(list_randomized[1])==0 || length(list_randomized[2])==0) {
    write.table(c(paste0(nrow(list_randomized[[1]]), condname1, "_rows"), 
            paste0(nrow(list_randomized[[2]])), condname2, "_rows"), 
            paste0(dir, "info.txt"), sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)
  }
  
  starttime7 <- Sys.time()
  plots <- plotting(list, list_randomized, df)
  pdf(paste0(dir, "amss_plots.pdf"), width=10, height=9)
  for (i in 1:length(plots)) {
    print(plots[[i]])
  }
  dev.off()
  print(paste0("TIME plot ", (Sys.time()-starttime7)))
  
}




if (is.null(opt$regfile)) { #single window given
  chromosome <- opt$chr
  window_s <- as.numeric(as.character(opt$start))
  window_e <- as.numeric(as.character(opt$end))
  p <- as.character(opt$out) #outdir
  sampleAnno <- read.csv(as.character(opt$sampleanno), sep="\t", header=TRUE)
  condname1 <- unique(sampleAnno$condition)[1]
  condname2 <- unique(sampleAnno$condition)[2]
  conds1 <- sampleAnno[which(sampleAnno$condition==condname1),1]
  conds2 <- sampleAnno[which(sampleAnno$condition==condname2),1]
  processWindow(chromosome, window_s, window_e)
} else { #file with several regions given
  window_file <- read.csv(opt$regfile, sep="\t", header=FALSE)
  print(paste0(nrow(window_file), " windows given"))
  p <- as.character(opt$out) #outdir
  sampleAnno <- read.csv(as.character(opt$sampleanno), sep="\t", header=TRUE)
  condname1 <- unique(sampleAnno$condition)[1]
  condname2 <- unique(sampleAnno$condition)[2]
  conds1 <- sampleAnno[which(sampleAnno$condition==condname1),1]
  conds2 <- sampleAnno[which(sampleAnno$condition==condname2),1]
  
  for (line in 1:nrow(window_file)) { #goint through every region of file
    chromosome <- window_file[line, 1]
    window_s <- as.numeric(as.character(window_file[line, 2]))
    window_e <- as.numeric(as.character(window_file[line, 3]))
    processWindow(chromosome, window_s, window_e)
  }
}



