#!/bin/bash

# SLURM tools

##################################################
# functions
##################################################

exitError()
{
    \rm -f /tmp/tmp.${user}.$$ 1>/dev/null 2>/dev/null
    echo "ERROR $1: $3" 1>&2
    echo "ERROR     LOCATION=$0" 1>&2
    echo "ERROR     LINE=$2" 1>&2
    exit $1
}

showWarning()
{
    echo "WARNING $1: $3" 1>&2
    echo "WARNING       LOCATION=$0" 1>&2
    echo "WARNING       LINE=$2" 1>&2
}

# function to launch and wait for job (until job finishes or a
# specified timeout in seconds is reached)
#
# usage: launch_job script timeout

function launch_job {
  local script=$1
  local timeout=$2
  local sacct_maxwait=90

  # check sanity of arguments
  test -f "${script}" || exitError 7201 ${LINENO} "cannot find script ${script}"
  if [ -n "${timeout}" ] ; then
      echo "${timeout}" | grep '^[0-9][0-9]*$' 2>&1 > /dev/null
      if [ $? -ne 0 ] ; then
          exitError 7203 ${LINENO} "timeout is not a number"
      fi
  fi

  # get out/err of SLURM job
  local out=`grep '^\#SBATCH --output=' ${script} | sed 's/.*output=//g'`
  local err=`grep '^\#SBATCH --error=' ${script} | sed 's/.*error=//g'`

  # submit SLURM job
  local res=`sbatch ${script}`
  if [ $? -ne 0 ] ; then
      exitError 7205 ${LINENO} "problem submitting SLURM batch job"
  fi
  echo "${res}" | grep "^Submitted batch job [0-9][0-9]*$" || exitError 7206 ${LINENO} "problem determining job ID of SLURM job"
  local jobid=`echo "${res}" | sed  's/^Submitted batch job //g'`
  test -n "${jobid}" || exitError 7207 ${LINENO} "problem determining job ID of SLURM job"

  # wait until job has finished (or maximum sleep time has been reached)
  if [ -n "${timeout}" ] ; then
      local secs=0
      local inc=2
      local job_status="UNKNOWN"
      while [ $secs -lt $timeout ] ; do
          echo "...waiting ${inc}s for SLURM job ${jobid} to finish (status=${job_status})"
          sleep ${inc}
          secs=$[$secs+${inc}]
          inc=60
          squeue_out=`squeue -o "%.20i %.20u %T" -h -j "${jobid}" 2>/dev/null`
          echo "${squeue_out}" | grep "^ *${jobid} " &> /dev/null
          if [ $? -eq 1 ] ; then
              break
          fi
          job_status=`echo ${squeue_out} | sed 's/.* //g'`
      done
  fi

  # make sure that job has finished
  squeue_out=`squeue -o "%.20i %.20u %T" -h -j "${jobid}" 2>/dev/null`
  echo "${squeue_out}" | grep "^ *${jobid} " &> /dev/null
  if [ $? -eq 0 ] ; then
      exitError 7207 ${LINENO} "batch job ${script} with ID ${jobid} on host ${slave} did not finish"
  fi

  # check for normal completion of batch job
  # Since the slurm data base may take time to update, wait until sacct_maxwait
  local sacct_wait=0
  local sacct_inc=30
  local sacct_log=sacct.${jobid}.log
  local sacct_status=1

  while [ $sacct_wait -lt $sacct_maxwait ] ; do
      sacct --jobs ${jobid} -p -n -b -D 2>/dev/null > ${sacct_log}
      # Check that sacct returns COMPLETED
      grep -v '|COMPLETED|0:0|' ${sacct_log} >/dev/null
      if [ $? -eq 0 ]; then
	  echo "Status not COMPLETED, waiting 30s for data base update"
	  sleep 30
      else
	  sacct_status=0
	  break
      fi
      sacct_wait=$[$sacct_wait+${sacct_inc}]
  done

  if [ $sacct_status -ne 0 ] ; then
      if [ -n "${out}" ] ; then
          echo "=== ${out} BEGIN ==="
          cat ${out} | /bin/sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"
          echo "=== ${out} END ==="
      fi
      if [ -n "${err}" ] ; then
          echo "=== ${err} BEGIN ==="
          cat ${err} | /bin/sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"
          echo "=== ${err} END ==="
      fi
      echo "=== ${sacct_log} BEGIN ==="
      cat ${sacct_log}
      echo "=== ${sacct_log} END ==="
      exitError 7209 ${LINENO} "batch job ${script} with ID ${jobid} on host ${slave} did not complete successfully"
  fi
  rm ${sacct_log}
}


