# Select items for lexical decision experiment
# Jelmer Borst, j.p.borst@rug.nl
# 15 04 2019




## Load data

setwd('~/Work/EM/LexicalDecision/Experiment/Material')
load('dlp-items.Rdata')
load('dlp-stimuli.Rdata')

#merge
stims <- merge(dlp.items,dlp.stimuli)

#keep potentially interesting stuff
stims <- stims[,c("spelling", "lexicality", "rt", "accuracy", "celex.frequency", "celex.frequency.lemma" ,"nchar","nsyl")]

#add nchar for nonwords
stims[stims$lexicality=='N','nchar'] <- nchar(as.character(stims[stims$lexicality=='N','spelling']))

#select only 5-8 letters
nrow(stims)

stims <- stims[stims$nchar %in% 4:8,]

nrow(stims)


#select high frequecy items:
stimsHF <- stims[stims$lexicality == 'W' & stims$celex.frequency >= 1000 & stims$accuracy > .85,] #can make this more extreme
stimsHF <- stimsHF[!is.na(stimsHF$rt),]

nrow(stimsHF)
mean(stimsHF$rt)
mean(stimsHF$accuracy)


#select low frequency items
stimsLF <- stims[stims$lexicality == 'W' & stims$celex.frequency > 3 & stims$celex.frequency < 25 & stims$accuracy > .85,] 
stimsLF <- stimsLF[!is.na(stimsLF$rt),]

nrow(stimsLF)
mean(stimsLF$rt)
mean(stimsLF$accuracy)


#select pseudowords from high frequency items
require(stringdist)
nonws <- stims[stims$lexicality == 'N',]

stimsPseudo <- data.frame()
toberemoved <- c()

for(word in stimsHF$spelling){
    
    #find closest match
    d <- stringdist(word, nonws$spelling)
    
    #1/2 matches
    tmp <- nonws[d<3,]
    tmp$d <- d[d<3]    
    
    #add nchar diff
    tmp$dn <- nchar(word) - tmp$nchar
    tmp <- tmp[tmp$dn ==0,] #only same length
    
    #sort based on d, accuracy
    tmp <- tmp[order(tmp$accuracy,decreasing=T),]
    tmp <- tmp[order(tmp$d),]
    
    #only allow same length
    if(nrow(tmp) > 0){
        stimsPseudo <- rbind(stimsPseudo,tmp[1,])
        #cat(word, as.character(tmp[1,]$spelling), nchar(word) - tmp[1,]$nchar,'\n')
       
    }else{
        cat('no same char match\n')
        toberemoved <- c(toberemoved, word)
    }
}

#remove HF words that couldn't be matched
stimsHF <- stimsHF[stimsHF$spelling %out% toberemoved,]



#add random letter strings
stimsRandom <- stimsLF[,c('spelling','lexicality', 'nchar')]
stimsRandom$lexicality <- 'N'
stimsRandom$spelling <- as.character(stimsRandom$spelling)

require(stringi)

for(i in 1:nrow(stimsRandom)){
    while(stimsRandom[i,]$spelling %in% dlp.items$spelling){
    #cat(i)
    #while(min(stringdist(stimsRandom[i,]$spelling, dlp.items$spelling))<2){
            
        stimsRandom[i,]$spelling <- stri_rand_shuffle(stimsRandom[i,]$spelling)
    }
}

#check once more
nrow(stimsHF)
mean(stimsHF$rt)
mean(stimsHF$acc)
nrow(stimsLF)
mean(stimsLF$rt)
mean(stimsLF$acc)
nrow(stimsPseudo)
mean(stimsPseudo$rt)
mean(stimsPseudo$acc)
nrow(stimsRandom)


require(gplots)
barplot2(c(mean(stimsHF$rt), mean(stimsLF$rt), mean(stimsPseudo$rt)),names.arg=c('HF','LF','Pseudo'),ylab='RT')
        



### generate stim files for each participant

#each trial takes 500 ms fix + 600 stim + 0 fb + 500 fix = 3.6 seconds. 250 trials/cond. 12 practice trials

#pick stuff for open sesame
stimsHF_OS <- stimsHF[,c('spelling','lexicality')]
names(stimsHF_OS) <- 'stimulus'
stimsHF_OS$cond <- 'HF'
stimsHF_OS$condition <- 1
stimsHF_OS$correct_response <- 'n'
stimsHF_OS <- stimsHF_OS[,c(1,3:5)]

stimsLF_OS <- stimsLF[,c('spelling','lexicality')]
names(stimsLF_OS) <- 'stimulus'
stimsLF_OS$cond <- 'LF'
stimsLF_OS$condition <- 2
stimsLF_OS$correct_response <- 'n'
stimsLF_OS <- stimsLF_OS[,c(1,3:5)]

stimsPseudo_OS <- stimsPseudo[,c('spelling','lexicality')]
names(stimsPseudo_OS) <- 'stimulus'
stimsPseudo_OS$cond <- 'Pseudo'
stimsPseudo_OS$condition <- 3
stimsPseudo_OS$correct_response <- 'm'
stimsPseudo_OS <- stimsPseudo_OS[,c(1,3:5)]

stimsRandom_OS <- stimsRandom[,c('spelling','lexicality')]
names(stimsRandom_OS) <- 'stimulus'
stimsRandom_OS$cond <- 'Random'
stimsRandom_OS$condition <- 4
stimsRandom_OS$correct_response <- 'm'
stimsRandom_OS <- stimsRandom_OS[,c(1,3:5)]

for(pp in 1:110){
    
    stimsHFpp <- stimsHF_OS[sample(1:nrow(stimsHF_OS), 242),]
    stimsLFpp <- stimsLF_OS[sample(1:nrow(stimsLF_OS), 242),]
    stimsPseudopp <- stimsPseudo_OS[sample(1:nrow(stimsPseudo_OS), 242),]
    stimsRandompp <- stimsRandom_OS[sample(1:nrow(stimsRandom_OS), 242),]
    
    block1 <- rbind(stimsHFpp[1:60,],stimsLFpp[1:60,],stimsPseudopp[1:60,],stimsRandompp[1:60,])
    block2 <- rbind(stimsHFpp[61:120,],stimsLFpp[61:120,],stimsPseudopp[61:120,],stimsRandompp[61:120,])
    block3 <- rbind(stimsHFpp[121:180,],stimsLFpp[121:180,],stimsPseudopp[121:180,],stimsRandompp[121:180,])
    block4 <- rbind(stimsHFpp[181:240,],stimsLFpp[181:240,],stimsPseudopp[181:240,],stimsRandompp[181:240,])
    
    block1 <- block1[sample(1:nrow(block1),240),]
    block2 <- block2[sample(1:nrow(block2),240),]
    block3 <- block3[sample(1:nrow(block3),240),]
    block4 <- block4[sample(1:nrow(block4),240),]
    
    write.csv(block1,paste('stims_LD', pp, '_block1.csv',sep=''),row.names=F)
    write.csv(block2,paste('stims_LD', pp, '_block2.csv',sep=''),row.names=F)
    write.csv(block3,paste('stims_LD', pp, '_block3.csv',sep=''),row.names=F)
    write.csv(block4,paste('stims_LD', pp, '_block4.csv',sep=''),row.names=F)
    
    training <- rbind(stimsHFpp[241:242,],stimsLFpp[241:242,],stimsPseudopp[241:242,],stimsRandompp[241:242,])
    training <- training[sample(1:nrow(training),8),]
    write.csv(training,paste('stims_LD', pp, '_practice.csv',sep=''),row.names=F)
    
}
