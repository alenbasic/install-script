#!/bin/bash

function ok_nok {
# Requires that variable "message" be set
status=$?
if [[ $status -eq 0 ]]
then
  printf "${GREEN}$message OK${NC}\n"
  printf "$message OK\n" >> /root/enosARM.log
else
  printf "${RED}$message   FAILED${NC}\n"
  printf "$message FAILED\n" >> /root/enosARM.log
  printf "\n\nLogs are stored in: /root/enosARM.log\n"
  exit 1
fi
sleep 1
}	# end of function ok_nok

function gettzentry {
# requires that the variable directory be set prior to call
# after call data needs to be pulled from entry after the call
if [ "$directory" != "$tzsource" ]
then
   printf "\033c"; printf "\n"
fi
ls $directory
finished=1
while [ $finished -ne 0 ]
do
   printf "\nTime Zone entries are case sensitive and must be entered exactly as above\n"
   printf "Enter your time zone item from the above list: "
   read entry
   if [ "$entry" == "" ] ; then entry="emptyentry" ; fi
   xyz=$(ls $directory | grep -x $entry) 
   if [ "$entry" == "$xyz" ]
   then
      finished=0
      timezonepath=$directory/$entry
      printf "\n"
   else
      printf "\nYour entry did not match an item in the list. Please try again\n"
   fi
done
}   # end of function gettzentry


function simple_yes_no {
# Requires that variable "prompt" be set
while true 
do
      printf "$prompt"
      read answer 
      answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
      case $answer in

      [y]* ) returnanswer=$answer
              break
              ;;

       [n]* ) returnanswer=$answer
              break
              ;;

      [q]* ) exit
              ;;  

      * )     printf "\nTry again, Enter [y,n] :\n"
              true="false"
              ;;
   esac
done
}   # end of function  simple_yes_no

function yes_no_input {
# Requires that variables "prompt" "message" and "verify" be set
while true 
do
     # (1)read command line argument
     printf "$prompt"     
     if [ $verify == "true" ]
     then
        read returnanswer          
        read -p "You entered \" $returnanswer \" is this correct? [y,n,q] :" answer
     else
        read answer
        returnanswer=$answer 
     fi
     # (2) handle the input we were given
     # if y then continue, if n then exit script with $message
     case $answer in
      [yY]* ) printf "\n"
              break;;

      [nN]* ) if [ $verify == "true" ]
              then
                 printf "$message\n"
                 true="false"
              else
                 printf "$message\n"
                 exit
              fi
              ;;

      [qQ]* ) exit
              ;;

      * )     if [ $verify == "true" ]
              then
                 printf "\nTry again.\n"
              else 
                 printf "\nTry again, Enter [y,n] :\n"
              fi
              true="false"
              ;;
   esac
done
}    # end of function yes_no_input


function installssd {
printf "\033c"; printf "\n"
printf "Connect a USB 3 external enclosure with a SSD or hard drive installed.\n"
printf "CAUTION: ALL data on this drive will be erased.\n"
prompt="\n\n${CYAN}Do you want to continue? [y,n]${NC} "
simple_yes_no

if [ $returnanswer == "y" ]
then
  printf "\nPlease wait for a few seconds.\n"
  sleep 10
  printf "\n${CYAN}The following storage devices were found on your Computer.${NC}\n\n"
  lsblk -f
  printf "\nOne of the devices will be listed as mmcblk0 or mmclbk1 and will have two partitions listed under it.\n"
  printf "One partition will be / and the other /boot.  That will be the device with the Operating System on it.\n"
  printf "\nThe other device will probably be listed as sda or something similar and is the target device.\n"
  printf "\nIf you changed your mind and do not want to partition and format a storage device, enter: abort\n"
  printf "If the storage device that was plugged in does not show up, enter: repeat\n"
  finished=1
  while [ $finished -ne 0 ]
  do
     printf "\n${CYAN}Enter target device name prefaced with /dev/ such as /dev/sda with no number at the end${NC} "
     read datadevicename
     if [ "$datadevicename" == "abort" ]
     then
        return 
     fi
     if [[ ${datadevicename:0:5} != "/dev/" ]] 
     then
        if [ "$datadevicename" == "repeat" ]
        then
           printf "\n\n"
        else
           printf "\n${CYAN}Input improperly formatted.  Try again.${NC}\n\n"
        fi
        lsblk -f
     else 
        finished=0
     fi
  done     
  
  ##### Determine data device size in MiB and partition ###
  printf "\n${CYAN}Partitioning, & formatting DATA storage device...${NC}\n"
  datadevicesize=$(fdisk -l | grep "Disk $datadevicename" | awk '{print $5}')
  ((datadevicesize=$datadevicesize/1048576))
  ((datadevicesize=$datadevicesize-1))  # for some reason, necessary for USB thumb drives
  printf "\n${CYAN}Partitioning DATA device $datadevicename...${NC}\n"
  message="\nPartitioning DATA devive $datadevicename  "
  printf "\ndatadevicename = $datadevicename     datadevicesize=$datadevicesize\n" >> /root/enosARM.log
  parted --script -a minimal $datadevicename \
  mklabel msdos \
  unit mib \
  mkpart primary 1MiB $datadevicesize"MiB" \
  quit
  ok_nok  # function call
  
  if [[ ${datadevicename:5:4} = "nvme" ]]
  then
    mntname=$datadevicename"p1"
  else
     mntname=$datadevicename"1"
  fi
  printf "\n\nmntname = $mntname\n\n" >> /root/enosARM.log
  printf "\n${CYAN}Formatting DATA device $mntname...${NC}\n"
  printf "\n${CYAN}If \"/dev/sdx contains a ext4 file system Labelled XXXX\" or similar appears, Enter: yes${NC}\n\n"
  message="\nFormatting DATA device $mntname   "
  mkfs.ext4 $mntname   2>> /root/enosARM.log
  e2label $mntname DATA
  ok_nok  # function call
    
   mkdir /server /serverbkup  2>> /root/enosARM.log
   chown root:users /server /serverbkup 2>> /root/enosARM.log
   chmod 774 /server /serverbkup  2>> /root/enosARM.log

   printf "\n${CYAN}Adding DATA storage device to /etc/fstab...${NC}"
   message="\nAdding DATA storage device to /etc/fstab   "
   cp /etc/fstab /etc/fstab-bkup
   uuidno=$(lsblk -o UUID $mntname)
   uuidno=$(echo $uuidno | sed 's/ /=/g')
   printf "\n# $mntname\n$uuidno      /server          ext4            rw,relatime     0 2\n" >> /etc/fstab
   ok_nok   # function call

   printf "\n${CYAN}Mounting DATA device $mntname on /server...${NC}"
   message="\nMountng DATA device $mntname on /server   "
   mount $mntname /server 2>> /root/enosARM.log
   ok_nok   # function call

   chown root:users /server /serverbkup 2>> /root/enosARM.log
   chmod 774 /server /serverbkup  2>> /root/enosARM.log
   printf "\033c"; printf "\n"
   printf "${CYAN}Data storage device summary:${NC}\n\n"
   printf "\nAn external USB 3 device was partitioned, formatted, and /etc/fstab was configured.\n"
   printf "This device will be on mount point /server and will be mounted at bootup.\n"
   printf "The mount point /serverbkup was also created for use in backing up the DATA device.\n"     
fi
}  # end of function installssd


function devicemodel {
   devicemodel=$(cat /proc/cpuinfo | grep "Raspberry Pi 4 Model B" | awk '{print $3,$4,$5,$6,$7}')
   if [[ $devicemodel == "Raspberry Pi 4 Model B" ]]
   then
      printf "dtparam=audio=on\n" >> /boot/config.txt
      printf "hdmi_drive=0\n" >> /boot/config.txt
      printf "\n${CYAN}On your Raspberry Pi 4 Model B, the HDMI audio was enabled.\n"
      printf "Only 1 HDMI port can have audio enabled at a time, HDMI 0 is enabled by default\n"
      printf "To switch audio to HDMI 1, as root edit /boot/config.txt and set hdmi_drive=1\n${NC}"
      printf "\nPress any Key to continue  "
      read -n 1 z
   fi
   
   devicemodel=$(cat /proc/cpuinfo | grep "Hardkernel ODROID-N2" | awk '{print $4}')
   if [[ $devicemodel == "ODROID-N2" ]]
   then
      pacman -S --noconfirm mali-utgard-meson-libgl-x11
   fi
   
   devicemodel=$(cat /proc/cpuinfo | grep "ODROID-XU4" | awk '{print $3}')
   if [[ $devicemodel == "ODROID-XU4" ]]
   then
      pacman -S --noconfirm odroid-xu3-libgl-headers odroid-xu3-libgl-x11 xf86-video-armsoc-odroid
   fi
   
}   # end of function devicemodel


function xfce4 {
   printf "\n${CYAN}Installing XFCE4 ...${NC}\n"
   message="\nInstalling XFCE4  "
   pacman -S --noconfirm --needed - < xfce4-pkg-list
   ok_nok  # function call
   cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
   cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
   systemctl enable lightdm.service
}   # end of function xfce4

function mate {
   printf "\n${CYAN}Installing Mate...${NC}\n"
   message="\nInstalling Mate  "
   pacman -S --noconfirm --needed - < mate-pkg-list
   ok_nok  # function call
   cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
   cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
   systemctl enable lightdm.service
}   # end of function mate

function kde {
   printf "\n${CYAN}Installing KDE Plasma...${NC}\n"
   message="\nInstalling KDE Plasma  "
   pacman -S --noconfirm --needed - < kde-pkg-list
   ok_nok  # function call
   cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
   cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
   systemctl enable lightdm.service
}   # end of function kde

function gnome {
   printf "\n${CYAN}Installing Gnome...${NC}\n"
   message="\nInstalling Gnome"
   pacman -S --noconfirm --needed - < gnome-pkg-list
   ok_nok  # function call
   systemctl enable gdm.service
}   # end of function gnome

function cinnamon {
  printf "\n${CYAN}Installing Cinnamon...${NC}\n"
  message="\nInstalling Cinnamon  "
  pacman -S --noconfirm --needed - < cinnamon-pkg-list
  ok_nok  # function call
  cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
  cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
  systemctl enable lightdm.service
}   # end of function cinnamon

function budgie {
  printf "\n${CYAN}Installing Budgie-Desktop...${NC}\n"
  message="\nInstalling Budgie-Desktop"
  pacman -S --noconfirm --needed - < budgie-pkg-list
  ok_nok  # function call
  cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
  cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
  systemctl enable lightdm.service
}  # end of function budgie

function lxqt {
   printf "\n${CYAN}Installing LXQT...${NC}\n"
   message="\nInstalling LXQT  "
   pacman -S --noconfirm --needed - < lxqt-pkg-list
   ok_nok  # function call
   cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
   cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
   systemctl enable lightdm.service
}   # end of function lxqt

function i3wm {
   printf "\n${CYAN}Installing i3-wm ...${NC}\n"
   message="\nInstalling i3-wm  "
   pacman -S --noconfirm --needed - < i3wm-pkg-list
   ok_nok  # function call
   cp lightdm-gtk-greeter.conf.default   /etc/lightdm/
   cp /etc/lightdm/lightdm-gtk-greeter.conf.default /etc/lightdm/lightdm-gtk-greeter.conf
   systemctl enable lightdm.service
}   # end of function i3wm


#################################################
# beginning of script
#################################################

##### check to see if script was run as root #####
if [ $(id -u) -ne 0 ]
then
   printf "\n\nPLEASE RUN THIS SCRIPT WITH sudo or as root\n\n"
   exit
fi

# Declare following global variables
# uefibootstatus=20
arch="e"
returnanswer="a"
prompt="b"
message="c"
verify="d"
# osdevicename="e"
# sshport=3
username="a"

# Declare color variables
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# create empty /root/enosARM.log
printf "    LOGFILE\n\n" > /root/enosARM.log


armarch="$(uname -m)"
case "$armarch" in
        armv7*) armarch=armv7h ;;
esac

finished=1
message=""
printf "\n${CYAN}Choose type of install ${NC}\n\n"
while [ $finished -ne 0 ]
do
   printf "1 Desktop Environment\n"
   printf "2 Headless server Environment\n"
   printf "\n$message"
   printf "\nEnter your choice of Environment "
   read installtype
   finished=0
   case $installtype in
      1) installtype="desktop" ;;
      2) installtype="server" ;;
      *) printf "${RED}ERROR:${NC} Out of range\n\n" 
         message="\nEnter a number, either 1 or 2 "
         finished=1 ;;
   esac
done

if [ "$installtype" == "desktop" ]
then
    printf "\n${CYAN}A Desktop Operating System with your choice of DE will be installed${NC}\n"
else
    printf "\n${CYAN}A headless server environment will be installed${NC}\n"
fi
sleep 4

pacman -Syy

### the following installs all packages needed to match the EndeavourOS base install
printf "\n${CYAN}Installing EndeavourOS Base Addons...${NC}\n"
message="\nInstalling EndeavourOS Base Addons  "
sleep 2
if [ "$installtype" == "desktop" ]
then
   pacman -S --noconfirm --needed - < base-addons
else
   pacman -S --noconfirm --needed - < server-addons
   pacman -Rn --noconfirm dhcpcd
fi
ok_nok   # function call


if [ "$installtype" == "desktop" ]
then

   #################### find and install endevouros-arm-mirrorlist  ############################
   printf "\n${CYAN}Find current endeavouros-mirrorlist...${NC}\n\n"
   message="\nFind current endeavouros-mirrorlist "
   sleep 1
   curl https://github.com/endeavouros-arm/repo/tree/master/endeavouros-arm/$armarch | grep endeavouros-arm-mirrorlist |sed s'/^.*endeavouros-arm-mirrorlist/endeavouros-arm-mirrorlist/'g | sed s'/pkg.tar.zst.*/pkg.tar.zst/'g |tail -1 > mirrors

   file="mirrors"
   read -d $'\x04' currentmirrorlist < "$file"


   printf "\n${CYAN}Downloading endeavouros-mirrorlist...${NC}"
   message="\nDownloading endeavouros-mirrorlist "
   wget https://github.com/endeavouros-arm/repo/raw/master/endeavouros-arm/$armarch/$currentmirrorlist 2>> logfile2
   ok_nok      # function call

   printf "\n${CYAN}Installing endeavouros-arm-mirrorlist...${NC}\n"
   message="\nInstalling endeavouros-arm-mirrorlist "
   pacman -U --noconfirm $currentmirrorlist &>> logfile2
   ok_nok    # function call

   printf "\n[endeavouros-arm]\nSigLevel = PackageRequired\nInclude = /etc/pacman.d/endeavouros-arm-mirrorlist\n\n" >> /etc/pacman.conf

   # cleanup
   if [ -a $currentmirrorlist ]
   then
      rm -f $currentmirrorlist
   fi

###################################################################################################################

   printf "\n${CYAN}Find current endeavouros-keyring...${NC}\n\n"
   message="\nFind current endeavouros-keyring "
   sleep 1
   curl https://github.com/endeavouros-arm/repo/tree/master/endeavouros-arm/$armarch |grep endeavouros-keyring |sed s'/^.*endeavouros-keyring/endeavouros-keyring/'g | sed s'/pkg.tar.zst.*/pkg.tar.zst/'g | tail -1 > keys 2>> /root/enosARM.log

   file="keys"
   read -d $'\04' currentkeyring < "$file"


   printf "\n${CYAN}Downloading endeavouros-keyring...${NC}"
   message="\nDownloading endeavouros-keyring "
   wget https://github.com/endeavouros-arm/repo/raw/master/endeavouros-arm/$armarch/$currentkeyring 2>> /root/enosARM.log
   ok_nok		# function call

   printf "\n${CYAN}Installing endeavouros-keyring...${NC}\n"
   message="Installing endeavouros-keyring "
   pacman -U --noconfirm $currentkeyring &>> /root/enosARM.log
   ok_nok		# function call
   #  cleanup
   if [ -a $currentkeyring ]
   then
      rm -f $currentkeyring
   fi
fi # boss fi
################# End of finding and installing endeavouros-keyring #########################

pacman -Syy    # sync new endeavouros mirrorlist just installed above

################   Begin user input  #######################
userinputdone=1
while [ $userinputdone -ne 0 ]
do 
   printf "\033c"; printf "\n"
   country=""; zone=""; city=""; city2=""
   
   tzsource=/usr/share/zoneinfo

   directory=$tzsource
   if [ -d $directory ]
   then
      gettzentry   # function call
      country=$entry    
   fi

   directory=$tzsource/$country
   if  [ -d $directory ]
   then   
      gettzentry   # function call
      zone=$entry
   fi

   directory=$tzsource/$country/$zone
   if [ -d $directory ]
   then
      gettzentry   # function call
      city=$entry
   fi

   directory=$tzsource/$country/$zone/$city
   if [ -d $directory ]
   then
      gettzentry   # function call
      city2=$entry
   fi
    
   ############### end of time zone entry ##################################

   finished=1
   while [ $finished -ne 0 ]
   do
      printf "\nEnter your desired hostname: "
      read host_name
      if [ "$host_name" == "" ] 
      then
         printf "\nEntry is empty, try again\n"
      else
          finished=0
      fi  
   done

   finished=1
   while [ $finished -ne 0 ]
   do 
      printf "\nEnter your desired user name: "
      read username
      if [ "$username" == "" ]
      then
         printf "\nEntry is empty, try again\n"
      else     
         finished=0
      fi
   done
   
   if [ "$installtype" == "desktop" ]
   then
      finished=1
      while [ $finished -ne 0 ]
      do 
         printf "\nEnter your Full Name: "
         read fullname
         if [ "$fullname" == "" ]
         then
            printf "\nEntry is empty, try again\n"
         else     
            finished=0
         fi
      done
  
   
      finished=1
      message=""
      printf "\nChoose which Desktop Environment to install\n\n"
      while [ $finished -ne 0 ]
      do
         printf "0 No Desktop Environment\n"
         printf "1 XFCE4\n"
         printf "2 Mate\n"
         printf "3 KDE Plasma\n"
         printf "4 Gnome\n"
         printf "5 Cinnamon\n"
         printf "6 Budgie-Desktop\n"
         printf "7 LXQT\n"
         printf "8 i3-wm"
         printf "\n$message"
         printf "\nEnter your choice of Desktop Environment "
         read denum
         finished=0
         case $denum in
            0) dename="none" ;;
            1) dename="xfce4" ;;
            2) dename="mate" ;;
            3) dename="kde" ;;
            4) dename="gnome" ;;
            5) dename="cinnamon" ;;
            6) dename="budgie" ;;
            7) dename="lxqt" ;;
            8) dename="i3wm" ;;
            *) printf "${RED}ERROR:${NC} Out of range\n\n" 
               message="\nEnter a number between 0 and 8 "
               finished=1 ;;
         esac
      done
   fi

############################################################
   
   if [ "$installtype" == "server" ]
   then
     finished=1
     while [ $finished -ne 0 ]
     do
        printf "\nEnter the desired SSH port between 8000 and 48000: "
        read sshport
        if [ "$sshport" -eq "$sshport" ] # 2>/dev/null
        then
             if [ $sshport -lt 8000 ] || [ $sshport -gt 48000 ]
             then
                printf "\nYour choice is out of range, try again\n"
             else
                finished=0
             fi
        else
           printf "\nYour choice is not a number, try again\n"
        fi
     done

     ethernetdevice=$(ip r | awk 'NR==1{print $5}')
     routerip=$(ip r | awk 'NR==1{print $3}')
     threetriads=$routerip
     xyz=${threetriads#*.*.*.}
     threetriads=${threetriads%$xyz}
     printf "\nSETTING UP THE STATIC IP ADDRESS FOR THE SERVER\n"
     finished=1
     while [ $finished -ne 0 ]
     do
       printf "\nFor the best router compatibility, the last octet should be between 150 and 250\n"   
       printf "Enter the last octet of the desired static IP address $threetriads"
       read lasttriad
       if [ "$lasttriad" -eq "$lasttriad" ] # 2>/dev/null
       then
          if [ $lasttriad -lt 150 ] || [ $lasttriad -gt 250 ]
          then
             printf "\n\nYour choice is out of range. Please try again\n"
          else         
            finished=0
          fi
       else
          printf "\n\nYour choice is not a number.  Please try again\n"
       fi
     done
     staticip=$threetriads$lasttriad
     staticipbroadcast+=$staticip"/24"
   fi  # boss fi
   
#######################################################   
   
   printf "\033c"; printf "\n"
   printf "\nTo review, you entered the following information:\n"
   printf "\nTime Zone = $country $zone $city $city2"
   printf "\nHost Name = $host_name"
   printf "\nUser Name = $username"
   
   if [ "$installtype" == "desktop" ]
   then
     printf "\nFull Name = $fullname"
     printf "\nDesktop Environment = $dename"
   fi
   if [ "$installtype" == "server" ]
   then
      printf "\nSSH  port = $sshport"
      printf "\nStatic IP = $staticip"
   fi
   
   prompt="\n\nIs this informatin correct? [y,n,q] "
   simple_yes_no
   if [ $returnanswer == "y" ]
   then
      userinputdone=0
   fi
done

###################   end user input  ######################




printf "\n${CYAN}Setting Time Zone...${NC}\n"
message="\nSetting Time Zone  "
ln -sf $timezonepath /etc/localtime 2>> /root/enosARM.log
ok_nok  # function call

printf "\n${CYAN}Enabling NTP...${NC}"
message="\nEnabling NTP   "
timedatectl set-ntp true &>> /root/enosARM.log
timedatectl timesync-status &>> /root/enosARM.log
ok_nok		# function call
sleep 1


printf "\n${CYAN}Syncing Hardware Clock${NC}\n\n"
hwclock -r
if [ $? == "0" ]
then
  hwclock --systohc 2>> /root/enosARM.log
  printf "\n${CYAN}hardware clock was synced${NC}\n"
else
  printf "\n${RED}No hardware clock was found${NC}\n"
fi


printf "\n${CYAN}Setting Locale...${NC}\n"
message="\nSetting locale "
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen 2>> /root/enosARM.log
printf "\nLANG=en_US.UTF-8\n\n" > /etc/locale.conf 
ok_nok   # function call




printf "\n${CYAN}Setting hostname...${NC}"
message="\nSetting hostname "
printf "\n$host_name\n\n" > /etc/hostname
ok_nok   # function call

printf "\n${CYAN}Configuring /etc/hosts...${NC}"
message="\nConfiguring /etc/hosts "
printf "\n127.0.0.1\tlocalhost\n" > /etc/hosts
printf "::1\t\tlocalhost\n" >> /etc/hosts
printf "127.0.1.1\t$host_name.localdomain\t$host_name\n\n" >> /etc/hosts
ok_nok  # function call

printf "\n${CYAN}Running mkinitcpio...${NC}\n"
mkinitcpio -P  2>> /root/enosARM.log


printf "\nEnter your ${CYAN}NEW ROOT${NC} password\n\n"
finished=1
while [ $finished -ne 0 ]
do
  if passwd ; then
      finished=0 ; echo
   else
      finished=1 ; printf "\nPassword entry failed, try again\n\n"
   fi
done

printf "\n${CYAN}Delete default username (alarm) and Creating a user...${NC}"
message="Delete default username (alarm) and Creating new user "
userdel -r alarm     #delete the default user from the image
if [ "$installtype" == "desktop" ]
then
   useradd -c $fullname -m -G users -s /bin/bash -u 1000 $username 2>> /root/enosARM.log
else
   useradd -m -G users -s /bin/bash -u 1000 $username 2>> /root/enosARM.log
fi
printf "\nEnter ${CYAN}USER${NC} password.\n\n"
finished=1
while [ $finished -ne 0 ]
do
  if passwd $username ; then
      finished=0 ; echo
   else
      finished=1 ; printf "\nPassword entry failed, try again\n\n"
   fi
done
ok_nok 

if [ "$installtype" == "desktop" ]
then
   printf "\n${CYAN}Adding user $username to sudo wheel...${NC}"
   message="Adding user $username to sudo wheel "
   printf "$username  ALL=(ALL:ALL) ALL" >> /etc/sudoers
   gpasswd -a $username wheel    # add user to group wheel
fi

printf "\n${CYAN}Creating ll alias...${NC}"
message="\nCreating ll alias "
printf "\nalias ll='ls -l --color=auto'\n\n" >> /etc/bash.bashrc
ok_nok  # function call

##################### desktop setup #############################

pacman -Syy

if [ "$installtype" == "desktop" ]
then
   systemctl enable NetworkManager
   mkdir -p /usr/share/endeavouros/backgrounds
   cp lightdmbackground.png /usr/share/endeavouros/backgrounds
   if [ $dename != "none" ]     
   then
      $dename      # run appropriate function for installing Desktop Environment
      pacman -S --noconfirm --needed welcome yay endeavouros-theming
      pacman -S --noconfirm --needed pahis inxi  eos-log-tool eos-update-notifier downgrade
   fi
   
   devicemodel  # check to see if the device is a Raspberry Pi 4 b, if so enable HDMI audio
   if [ $dename == "i3wm" ]
   then 
      cd /home/$username
      sudo -u $username mkdir /home/$username/.config
      sudo -u $username git clone https://github.com/endeavouros-team/i3-EndeavourOS.git
      cd i3-EndeavourOS
      sudo -u $username cp -R .config/* /home/$username/.config/
      sudo -u $username cp .Xresources /home/$username/
      sudo -u $username chmod -R +x /home/$username/.config/i3/scripts
      cd
      sudo -u $username rm -rf /home/$username/i3-EndeavourOS
   fi
fi # boss fi

########################### end of desktop setup ##############################

################## server setup ####################

if [ "$installtype" = "server" ]
then
   # create /etc/netctl/ethernet-static file with user supplied static IP
   printf "\n${CYAN}Creating configuration file for static IP address...${NC}"
   message="\nCreating configuration file for static IP address "
   
   #ethernetdevice=$(ip r | awk 'NR==1{print $5}')
   if [[ ${ethernetdevice:0:3} == "eth" ]]
   then
      rm /etc/systemd/network/eth*
   fi
   
   if [[ ${ethernetdevice:0:3} == "enp" ]]
   then
      rm /etc/systemd/network/enp*
   fi
   ethernetconf="/etc/systemd/network/$ethernetdevice.network"
   printf "[Match]\n" > $ethernetconf
   printf "Name=$ethernetdevice\n\n" >> $ethernetconf
   printf "[Network]\n" >> $ethernetconf
   printf "Address=$staticipbroadcast\n" >> $ethernetconf
   printf "Gateway=$routerip\n" >> $ethernetconf
   printf "DNS=$routerip\n" >> $ethernetconf
   printf "DNS=8.8.8.8\n" >> $ethernetconf
   printf "DNSSEC=no\n" >> $ethernetconf
   

   printf "\n${CYAN}Configure SSH...${NC}"
   message="\nConfigure SSH "
   sed -i "/Port 22/c Port $sshport" /etc/ssh/sshd_config
   sed -i '/PermitRootLogin/c PermitRootLogin no' /etc/ssh/sshd_config
   sed -i '/PasswordAuthentication/c PasswordAuthentication yes' /etc/ssh/sshd_config
   sed -i '/PermitEmptyPasswords/c PermitEmptyPasswords no' /etc/ssh/sshd_config
   systemctl disable sshd.service 2>> /root/enosARM.log
   systemctl enable sshd.service 2>>/dev/null
   ok_nok    # function call


   printf "\n${CYAN}Enable ufw firewall...${NC}\n"
   message="\nEnable ufw firewall "
   ufw logging off 2>/dev/null
   ufw default deny 2>/dev/null
   ufwaddr=$threetriads
   ufwaddr+="0/24" 
   ufw allow from $ufwaddr to any port $sshport
   ufw enable 2>/dev/null
   systemctl enable ufw.service 2>/dev/null 
   ok_nok  # function call
   
   prompt="\n\n${CYAN}Do you want to partition and format a USB 3 DATA SSD and auto mount it at bootup? [y,n] ${NC}"
   simple_yes_no
   if [ $returnanswer == "y" ]
   then
      installssd
   fi
   
fi # boss fi

##################### end of server setup ############################

# rebranding to EndeavourOS
sed -i 's/Arch/EndeavourOS/' /etc/issue
sed -i 's/Arch/EndeavourOS/' /etc/arch-release
 sed -i -e s'|^DISTRIB_ID=.*$|DISTRIB_ID=EndeavourOS|' -e s'|^DISTRIB_DESCRIPTION=.*$|DISTRIB_DESCRIPTION=\"EndeavourOS Linux\"|' /etc/lsb-release
 sed -i -e s'|^NAME=.*$|NAME=\"EndeavourOS\"|' -e s'|^PRETTY_NAME=.*$|PRETTY_NAME=\"EndeavourOS\"|' -e s'|^HOME_URL=.*$|HOME_URL=\"https://endeavouros.com\"|' -e s'|^DOCUMENTATION_URL=.*$|DOCUMENTATION_URL=\"https://endeavouros.com/wiki/\"|' -e s'|^SUPPORT_URL=.*$|SUPPORT_URL=\"https://forum.endeavouros.com\"|' -e s'|^BUG_REPORT_URL=.*$|BUG_REPORT_URL=\"https://github.com/endeavouros-team\"|' -e s'|^LOGO=.*$|LOGO=endeavouros|' /usr/lib/os-release
if [ ! -d "/etc/pacman.d/hooks" ]
then
   mkdir /etc/pacman.d/hooks  
fi
cp lsb-release.hook os-release.hook  /etc/pacman.d/hooks/
chmod 755 /etc/pacman.d/hooks/lsb-release.hook /etc/pacman.d/hooks/os-release.hook

rm -rf /root/EndeavourOS-ARM

printf "\n\n${CYAN}Installation is complete!${NC}\n\n"
if [ "$installtype" == "desktop" ]
then
   printf "\nRemember to use your new root password when logging in as root\n"
   printf "\nRemember to use your new user name and password when logging into Lightdm\n"
   printf "\nNo firewall was installed. Consider installing a firewall with eos-Welcome\n"
else
   printf "\nRemember your new user name and password when remotely logging into the server\n"
   printf "\nSSH server was installed and enabled to listen on port $sshport\n"
   printf "\nufw was installed and enabled with \"logging off\", the default \"deny\", and the following rule"
   printf "\nufw allow from $ufwaddr to any port $sshport\n"
   printf "\nWhich will only allow access to the server from your local LAN on the specified port\n"
fi
printf "Pressing any key will exit the script and reboot the computer.\n"

printf "\nPress any key to continue \n\n"
read -n1 x


systemctl reboot

exit  # end of script

