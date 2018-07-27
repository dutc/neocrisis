# Neo Crisis Provisioner

This is a small Ansible script to setup environment needed for our awesome Neo Crisis because the world is ending and we have no time to be shelling into servers to do all the hard work manually :)

This provisioner expects the target machine to be a Ubuntu18.04 but does not validates that(feel free to try on different flavors/versions).

## Development

The provided `Vagrantfile` will run the Ansible provisioner when the machine is created having the full project setup.

TLDL:

```
vagrant up
vagrant ssh
cd /vagrant
```

The `/vagrant` folder is synced with the host machine so you can edit files on your computer and run on the VM from there.

The `/var/www/neocrisis/` is pulled from Github during deployment so changing files on your local computer wont affect it.

### To be continued...

A `virtualenv` for `/var/www/neocrisis` and NGINX or some other stable way to run the Flask app coming soon
