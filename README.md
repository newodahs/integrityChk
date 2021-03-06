# integrityChk 

A quick script that acts as a very basic IDS for a local FreeBSD system.  The concept is to generate a baseline set of hash values for a specific set of binaries/directories, archive them, and verify them at a later time.

# Setup/Usage

To get going with integrityChk, simply place the script local to the box you wish to check and execute it.
 * The first execution should be done with -g | --generate
  * This will generate your baseline archive of hashes - archive is called osChk.tgz
   * For permissions reasons, it's best to run as an elevated user (sudo, root, etc...)
   * Archive is now generated in /tmp by default as osChk.tgz - make sure you can write to this directory
  * This also copies the integrityChk script into the archive, effectively making the archive a all-in-one package for later verification
  * IMPORTANT NOTE: You will be prompted to supply a secret key during execution; REMEMBER THIS KEY - IT CAN NOT BE RECOVERED IN ANY REASONABLE WAY
  * IMPORTANT NOTE: Do NOT leave this archive on the system you generate on; instead secure it offline for later use in later verification
 * To verify the system integrity at a later time, simply copy the archive generated with the -g | --generate command and extract it on the system it was created on
  * It's recommended to create a temporary location to extract the archive to as it is packed in a flat way with little hierarchy
  * Within this archive you will find a copy of the integrityChk script, use this script to verify the system by running it directly with -v | --validate
   * It is a best practice to use the script that is packaged with the archive for verification
  * IMPORTANT NOTE: To execute the validation successfully you will be required to use the secret key that you set when you generated the original archive
  * IMPORTANT NOTE: If you need to update/regenerate the baseline archive, either re-download this script OR use the archived version of the script
  
# Release Notes

Sept-08-2016
Various fixes made, changed default pathing - review Setup/Usage above

Sept-2016
First public revision of this script.  Base functionality is as follows:
 * Ability to generate a baseline hash archive
 * Ability to validate current system against baseline hash archive
