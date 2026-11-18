# Ansible windows_sysinternals role

## Overview

The role downloads the Sysinternals suite into the guest, verifies the pinned sha256, extracts the
suite to `windows_sysinternals_dir`, adds the directory to the machine PATH, and accepts the EULA
for the connection user and for new users.

The download URL is unversioned. When Microsoft updates the suite, the download fails with a
checksum error. Set `windows_sysinternals_sha256` to the new hash and run the role again.

## Variables

* `windows_sysinternals_url`: Download URL of the suite zip.
* `windows_sysinternals_sha256`: Expected sha256 of the zip. The role re-extracts the suite when the
  installed copy came from a different hash.
* `windows_sysinternals_dir`: Install directory (default `C:\Tools\Sysinternals`).
* `windows_sysinternals_temp_dir`: Directory for the downloaded zip (default `C:\Temp`).

## Example

```yml
- name: install the Sysinternals suite
  hosts: windows
  gather_facts: false
  roles:
    - windows_sysinternals
```