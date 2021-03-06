#' align
#'
#' Align reads on the hubrid reference genome.
#'
#' @author Robin H. van der Weide, \email{r.vd.weide@nki.nl}
#' @param exp The tagMeppr-object of a sample.
#' @param ref A reference object of \code{\link{makeIndex}} or \code{\link{loadIndex}}.
#' @param cores The number of threads used in the mapping-stage.
#' @param dedup Remove suspected PCR-duplicates?
#' @param empericalCentre The location of the center of the inserted sequence
#' in the transposon.fa. This is needed to find the orientation of the
#' insertion. Can be T, F or numeric:
#' \describe{
#'   \item{TRUE}{Will find it automatically}
#'   \item{FALSE}{Will take the middle of the transposon.fa. This doesn't
#' have to be the case when you loaded a BAC containing the insertion.}
#'   \item{numeric}{Will use this number as the postion of the middle.}
#' }
#' @param verbose Do you want a more chatty function?
#' @param BWA_path A string to the complete BWA-path.
#' @param samtools_path A string to the complete samtools-path.
#' @examples
#' \dontrun{
#' reference_hg19_PB = makeIndex(indexPath = '/home/A.Dent/analysis42/',
#'                               bsgenome = 'BSgenome.Hsapiens.UCSC.hg19',
#'                               ITR = 'PiggyBac')
#'
#' C9 = newTagMeppr(F1 = 'clone9_FWD_R1.fq.gz',
#'                  F2 = 'clone9_FWD_R2.fq.gz',
#'                  R1 = 'clone9_REV_R1.fq.gz',
#'                  R2 = 'clone9_REV_R2.fq.gz',
#'                  name = "clone9",
#'                  protocol = 'PiggyBac')
#'
#' align(exp = C9, ref = reference_hg19_PB, cores = 30, empericalCentre = T)
#' }
#' @return The object will be updated with the following slots:
#' \describe{
#' \item{alignmentFolder}{The path to the folder of BAM-files}
#' \item{insertName}{The name of the transposon in the hybrid reference}
#' \item{seqinfo}{The seqinfo of the hybrid reference}
#' \item{FWDBAM}{GenomicAlignments of the mapping of forward reads}
#' \item{REVBAM}{GenomicAlignments of the mapping of reverse reads}
#' \item{alignedReadsFWD}{Granges-oject with informative forward reads}
#' \item{alignedReadsREV}{Granges-oject with informative reverse reads}
#' \item{insertionMid}{The used position of the middle of the insertion}
#'}
#'
#' @importFrom dplyr bind_rows full_join
#' @importFrom GenomicRanges makeGRangesFromDataFrame
#' @importFrom GenomicAlignments readGAlignments
#' @importFrom reshape2 colsplit
#' @importFrom Rsamtools ScanBamParam
#' @importFrom utils read.delim
#' @importFrom GenomeInfoDb seqlengths
#' @importFrom stats complete.cases
#' @importFrom S4Vectors mcols
#' @importFrom BiocGenerics strand
#' @export
#'
align = function(exp, ref, cores = 20, dedup = T, empericalCentre = F, BWA_path = NULL, samtools_path = NULL, verbose = F){

  BWA <- NULL
  if(is.null(BWA_path)){
    BWA <- system('which bwa', intern = T)
  } else if(!is.null(BWA_path)){
    BWA <- BWA_path
  } else {
    stop('bwa not found')
  }


  SAMTOOLS <- NULL
  if(is.null(samtools_path)){
    SAMTOOLS <- system('which samtools', intern = T)
  } else if(!is.null(samtools_path)){
    SAMTOOLS <- samtools_path
  } else {
    stop('samtools not found')
  }

   folder = paste0('/tmp/',runIDgen(1))

  while(dir.exists(folder)){
    folder = paste0('/tmp/',runIDgen(1))
  }

  dir.create(folder)

  cmd_1 = paste(sep = " ",
                BWA,
                "mem -v 1 -Y -M -t ",
                cores,
                ref$index,
                exp$F1,
                exp$F2,
                "|",
                SAMTOOLS,
                "view -Sb -F 4 -",
                "|",
                SAMTOOLS,
                "sort -m 1G -@",
                floor(cores/10)+1,
                "-O bam -T",
                paste0(folder,
                       "/FWD.TMP"),
                "- >",
                paste0(folder,
                       "/FWDtmp.bam;"),
                SAMTOOLS,
                "index",
                paste0(folder,
                       "/FWDtmp.bam;"),
                SAMTOOLS,
                "rmdup",
                paste0(folder,
                       "/FWDtmp.bam"),
                paste0(folder,
                       "/FWD.bam"))

  if(verbose){message('Mapping FWD')}
  blabla = system(cmd_1, intern = F, ignore.stdout = T, ignore.stderr = T)
  bla = file.remove(paste0(folder,
                           "/FWDtmp.bam"))
  bla = file.remove(paste0(folder,
                           "/FWDtmp.bam.bai"))

  cmd_2 = paste(sep = " ",
                BWA,
                "mem -v 1 -Y -M -t ",
                cores,
                ref$index,
                exp$R1,
                exp$R2,
                "|",
                SAMTOOLS,
                "view -Sb -F 4 -",
                "|",
                SAMTOOLS,
                "sort -m 1G -@",
                floor(cores/10)+1,
                "-O bam -T",
                paste0(folder,
                       "/REV.TMP"),
                "- >",
                paste0(folder,
                       "/REVtmp.bam;"),
                SAMTOOLS,
                "index",
                paste0(folder,
                       "/REVtmp.bam;"),
                SAMTOOLS,
                "rmdup",
                paste0(folder,
                       "/REVtmp.bam"),
                paste0(folder,
                       "/REV.bam"))

  if(verbose){message('Mapping REV')}
  blabla = system(cmd_2, intern = F, ignore.stdout = T, ignore.stderr = T)
  bla = file.remove(paste0(folder,
                           "/REVtmp.bam"))
  bla = file.remove(paste0(folder,
                           "/REVtmp.bam.bai"))


  # select FWD reads mapping to integration ------------------------------------
  if(verbose){message('Filtering FWD')}
  system2(command = SAMTOOLS, args = c('view',
                                         '-H',
                                         paste0(folder,"/FWD.bam")),
          stdout = paste0(folder,"/FWD.sam"))

  system2(command = SAMTOOLS, args = c('view',
                                         paste0(folder,"/FWD.bam")),
          stdout = paste0(folder,"/FWDgrep.sam"))

  system2(command = 'grep', args = c('-i',
                                     ref$insertName,
                                     paste0(folder,"/FWDgrep.sam")),
          stdout = paste0(folder,"/FWDgrep2.sam"))

  system(paste0('cat ',
                paste0(folder,"/FWDgrep2.sam"),
                " >> ",
                paste0(folder,"/FWD.sam"))  )

  system2(command = SAMTOOLS, args = c('view',
                                         '-Sb',
                                         paste0(folder,"/FWD.sam")),
          stdout = paste0(folder,"/FWD.bam"))

  bla = file.remove(paste0(folder,
                           "/FWDgrep2.sam"))
  bla = file.remove(paste0(folder,
                           "/FWDgrep.sam"))
  bla = file.remove(paste0(folder,
                           "/FWD.sam"))

  # select REV reads mapping to integration ------------------------------------
  if(verbose){message('Filtering REV')}
  system2(command = SAMTOOLS, args = c('view',
                                         '-H',
                                         paste0(folder,"/REV.bam")),
          stdout = paste0(folder,"/REV.sam"))

  system2(command = SAMTOOLS, args = c('view',
                                         paste0(folder,"/REV.bam")),
          stdout = paste0(folder,"/REVgrep.sam"))

  system2(command = 'grep', args = c('-i',
                                     ref$insertName,
                                     paste0(folder,"/REVgrep.sam")),
          stdout = paste0(folder,"/REVgrep2.sam"))

  system(paste0('cat ',
                paste0(folder,"/REVgrep2.sam"),
                " >> ",
                paste0(folder,"/REV.sam"))  )

  system2(command = SAMTOOLS, args = c('view',
                                         '-Sb',
                                         paste0(folder,"/REV.sam")),
          stdout = paste0(folder,"/REV.bam"))

  bla = file.remove(paste0(folder,
                           "/REVgrep2.sam"))
  bla = file.remove(paste0(folder,
                           "/REVgrep.sam"))
  bla = file.remove(paste0(folder,
                           "/REV.sam"))


  # clean ----------------------------------------------------------------------
  exp$alignmentFolder = folder
  exp$insertName = ref$insertName
  exp$seqinfo = ref$seqinfo

  # post align  ------------------------------------
  if(verbose){message('Running postAlign')}
  FWDBAM <- GenomicAlignments::readGAlignments(paste0(exp$alignmentFolder,"/FWD.bam"),
                                               param=Rsamtools::ScanBamParam(tag=c("SA",
                                                                                   "XA")),
                                               use.names = T)
  cassInfo = FWDBAM@seqinfo[exp$insertName]
  S4Vectors::mcols(FWDBAM)$readName = names(FWDBAM); names(FWDBAM) = NULL

  REVBAM <- GenomicAlignments::readGAlignments(paste0(exp$alignmentFolder,"/REV.bam"),
                                               param=Rsamtools::ScanBamParam(tag=c("SA",
                                                                                   "XA")),
                                               use.names = T)
  cassInfo = REVBAM@seqinfo[exp$insertName]
  S4Vectors::mcols(REVBAM)$readName = names(REVBAM); names(REVBAM) = NULL

  exp$FWDBAM = FWDBAM
  exp$REVBAM = REVBAM

  BAMlist = list('FWD' = FWDBAM, 'REV' = REVBAM )
  BAMlist = lapply(BAMlist, as.data.frame)

  if(empericalCentre == T){
    cassMid = empericalTransposonCentre(exp, ref)
  } else if(empericalCentre == F){
    cassLen = cassInfo@seqlengths
    cassMid = round(cassLen/2)

  } else if( is.numeric(empericalCentre) ){
    # cool: check the number
    if(empericalCentre > GenomeInfoDb::seqlengths(cassInfo)){
      stop('The given trans-centre is larger than the size of the sequence!')
    } else {
      cassMid = empericalCentre
    }
  } else {
    stop('empericalCentre must be T, F or numeric!')
  }

# catch for EC == NA
  if(is.na(cassMid)){
    cassMid = GenomeInfoDb::as.data.frame(ref$seqinfo[ref$insertName])[,1]/2
  }


  SAlist  = lapply(BAMlist, function(x){

    tmpSplit = splitXSA(x, field = 'SA')

    tmpSA = reshape2::colsplit(tmpSplit$XA, pattern = ',',names = c('S','P','St','C','Q','X'))
    tmpSA$readName = tmpSplit$RN

    tmpSA = tmpSA[stats::complete.cases(tmpSA), ]

    alignmentsSA = NULL
    if(nrow(tmpSA) > 0){
      alignmentsSA <- GenomicAlignments::GAlignments(seqnames = tmpSA$S,
                                                     pos = as.integer(tmpSA$P),
                                                     cigar = tmpSA$C,
                                                     strand = BiocGenerics::strand(tmpSA$St))
      S4Vectors::mcols(alignmentsSA)$readName = tmpSA$readName
      alignmentsSA = as.data.frame(alignmentsSA)
    } else {
      alignmentsSA = NULL
    }
    alignmentsSA
  })

  XAlist  = lapply(BAMlist, function(x){

    tmpSplit = splitXSA(x, field = 'XA')

    tmpSplit$XA = gsub(tmpSplit$XA, pattern = '\\+', replacement = '+,')
    tmpSplit$XA = gsub(tmpSplit$XA, pattern = '\\-', replacement = '-,')

    tmpXA = reshape2::colsplit(tmpSplit$XA, pattern = ',',names = c('S','St','P','C','Q','X'))
    tmpXA$X <- NULL
    tmpXA$readName = tmpSplit$RN

    tmpXA = tmpXA[stats::complete.cases(tmpXA), ]
    alignmentsXA = NULL
    if(nrow(tmpXA) > 0){
      alignmentsXA <- GenomicAlignments::GAlignments(seqnames = tmpXA$S,
                                                     pos = as.integer(tmpXA$P),
                                                     cigar = tmpXA$C,
                                                     strand = BiocGenerics::strand(tmpXA$St))
      S4Vectors::mcols(alignmentsXA)$readName = tmpXA$readName
      alignmentsXA = as.data.frame(alignmentsXA)
    } else {
      alignmentsXA = NULL
    }
    alignmentsXA
  })


  # combine main, SA and XA
  mainCorpus = lapply(BAMlist, function(x){
    x$SA <- NULL
    x$XA <- NULL
    x
  })

  combined = lapply(c('FWD', 'REV'), function(i){
    combined = list(mainCorpus[[i]],SAlist[[i]],XAlist[[i]])

    combined <- suppressWarnings(dplyr::bind_rows(combined))

  })


  alignedReadsFWD = GenomicRanges::makeGRangesFromDataFrame( combined[[1]],
                                                                 keep.extra.columns = T)
  alignedReadsREV = GenomicRanges::makeGRangesFromDataFrame( combined[[2]],
                                                                 keep.extra.columns = T)




  #################################################################### ITRs
  # get a GRanges ofthe two arms: this biostrings should be in the ref-object
  ITRpadRange = ref$NpadRange

  #################################################################### prettyBam
  ### FWD

  BiocGenerics::strand(alignedReadsFWD) = "*"
  alignedReadsFWDlist =  GenomicRanges::split(alignedReadsFWD, ~ readName)
  alignedReadsFWDlist = GenomicRanges::reduce(alignedReadsFWDlist)

  beforePAD = IRanges::start(alignedReadsFWDlist[seqnames(alignedReadsFWDlist) == exp$insertName]) < IRanges::start(ITRpadRange)
  S4Vectors::mcols(alignedReadsFWDlist)$beforePad = beforePAD
  alignedReadsFWD <- IRanges::stack(alignedReadsFWDlist, "readName")

  alignedReadsFWD$beforePad =  vapply(alignedReadsFWD$beforePad , any, FUN.VALUE = logical(1) )

  ### REV


  BiocGenerics::strand(alignedReadsREV) = "*"
  alignedReadsREVlist =  GenomicRanges::split(alignedReadsREV, ~ readName)
  alignedReadsREVlist = GenomicRanges::reduce(alignedReadsREVlist)

  beforePAD = IRanges::start(alignedReadsREVlist[seqnames(alignedReadsREVlist) == exp$insertName]) < IRanges::start(ITRpadRange)
  S4Vectors::mcols(alignedReadsREVlist)$beforePad = beforePAD
  alignedReadsREV <- IRanges::stack(alignedReadsREVlist, "readName")

  alignedReadsREV$beforePad =  vapply(alignedReadsREV$beforePad , any, FUN.VALUE = logical(1) )


  #########################################################################dedup
  if(verbose){message('Running dedup')}
  exp$dedup = F
  if(dedup){
    exp$dedup = T
    alignedReadsFWD = dedupAR(alignedReadsFWD)
    alignedReadsREV = dedupAR(alignedReadsREV)
  }


  ##################################################################### assigner
  exp$alignedReadsFWD = alignedReadsFWD
  exp$alignedReadsREV = alignedReadsREV
  exp$insertionMid = cassMid

  tmp = exp
  # get arguments
  name <- sapply(match.call(expand.dots=TRUE)[-1], deparse)
  #find argument postion for exp
  AP = which(names(name) == 'exp')

  assign(name[AP], tmp, envir = parent.frame())

  invisible(tmp)

}
