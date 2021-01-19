(import os)
(import paramiko)
(import getpass)
(import subprocess)
(import [os [listdir]])
(import [os.path [isfile join]])
(import [scp [SCPClient]])


(setv *remote-directory* None)


(defn get-remote-directories [client]
  "get the directories of the remote machine."
  (setv (, stdin stdout stderr) (client.exec-command (+ "cd " *remote-directory* " && tree -dfi")))
  (setv paths [])
  (for [folder stdout]
    (if (and (= folder ".") (= folder ""))
        (continue))
    (setv folder (folder.strip "\n"))
    (setv folder (folder.lstrip "\n"))
    (.append paths folder))
  (setv paths (list (filter (fn [s] (and (!= "" s) (in "" s))) paths)))
  (setv paths (remove-superfolders paths))
  paths)


(defn remove-superfolders [folders]
  "remove from `folders` those which contain other folders"
  (setv to-remove [])
  (for [folder1 folders]
    (for [folder2 (list (- (set folders) (set folder1)))]
      (if (in folder1 folder2)
          (if (in folder1 to-remove)
              (continue))
          (.append to-remove folder1))))
  (list (- (set folders) (set to-remove))))


(defn get-remote-inventory [client paths]
  "get the local inventory represented as a dict"
  (setv remote-inventory (dict))
  (for [path paths]
    (setv (, stdin stdout stderr) (client.exec-command (+ "cd " *remote-directory* path "&& ls ")))
    (setv items [])
    (for [item stdout]
      (.append items (.strip item "\n")))
    (setv path (+ "." path))    ; for compatibility with local paths
    (assoc remote-inventory path (set items)))
  remote-inventory)


(defn get-local-inventory []
  (setv mypath (os.path.relpath (os.getcwd))) ; NOTE if you're running this in a REPL, use (os.chdir "path")
  (setv inventory (dict))
  (for [(, folder _ file) (os.walk mypath)]
    (if (= folder mypath)
        (continue))
    (if (or (in " " folder) (not (in "\\" folder)))
        (setv folder (.replace folder " " "\\ ")))
    (assoc inventory folder (set file)))
  inventory)


(defn diff-directories [local-inventory remote-inventory]
  (setv local-paths (.keys local-inventory))
  (setv remote-paths (.keys remote-inventory))

  (setv in-local-not-in-remote (dict))
  (setv in-remote-not-in-local (dict))

  (for [local-path local-paths]
    (setv local-files (local-path local-inventory))
    (if (in local-path remote-paths)
        (do
          (setv remote-files (local-path remote-inventory))
          (if (!= local-files remote-files)
              (do
                (assoc in-local-not-in-remote local-path (- local-files remote-files))
                (assoc in-remote-not-in-local local-path (- remote-files local-files)))))
        (assoc in-local-not-in-remote local-path local-files)))
  (for [remote-path remote-paths]
    (setv remote-files (remote-path remote-inventory))
    (if (not (in remote-path local-paths))
        (assoc in-remote-not-in-local remote-path remote-files)))
  (setv in-local-not-in-remote (refine-diffed in-local-not-in-remote))
  (setv in-remote-not-in-local (refine-diffed in-remote-not-in-local))
  (, in-local-not-in-remote in-remote-not-in-local))


(defn refine-diffed [inventory]
  (setv keys (cut (list (.keys inventory))))
  (for [key keys]
    (if (or (= (key inventory) (set)) (= (key inventory) (dict ".DS-Store")))
        (del (get inventory key))))
  (return inventory))


(defn make-missing-local-directory [remote-path-list]
  (for [remote-path remote-path-list]
    (if (in "\\" remote-path)
        (= remote-path (.replace remote-path "\\" "")))
    (if (not (os.path.exists remote-path))
        (do
          (print "creating" (+ remote-path "..."))
          (os.makedirs remote-path)))))


(defn make-missing-remote-directory [client local-path-list]
  (for [local-path local-path-list]
    (setv local-path (cut local-path 1))
    (setv (, stdout -) (.exec-command client (+ "ls " *remote-directory* local-path)))
    (if (= (list stdout) (list))
        (.exec-command client (+ "mkdir -p " *remote-directory* local-path)))))


(defn exec-scp [scp-client in-local-not-in-remote in-remote-not-in-local]
  ;; upload
  (for [(, local-path local-files) (.items in-local-not-in-remote)]
    (setv remote-target-path (os.path.join *remote-directory* (cut local-path 2)))
    (for [local-file local-files]
      (print (+ "uploading" local-file "..."))
      (setv local-file-with-path (os.path.join local-path local-file))
      (.put scp-client local-file-with-path :recursive False :remote-path remote-target-path)))

  ;; download
  (for [(, remote-path remote-files) (.items in-remote-not-in-local)]
    (setv remote-path (.replace remote-path "\\" ""))
    (setv local-target-path (os.path.join (os.getcwd) (cut remote-path 2)))
    (for [remote-file remote-files]
      (print (+ "downloading" remote-file "..."))
      (setv remote-file-with-path (os.path.join *remote-directory* (cut remote-path 2) remote-file))
      (.get scp-client remote-file-with-path :recursive False :local-path local-target-path))))


(defmain []
  (global *remote-directory*)

  ;; make an ssh client
  (setv ssh-client (paramiko.SSHClient))
  (setv remote-address (input "Enter remote address: "))
  (setv remote-username (input "Enter remote username: "))
  (setv remote-port (input "Enter remote port: "))
  (setv remote-password (getpass.getpass "Enter remote password: "))
  (setv *remote-directory* (input "Enter remote directory (absolute path): "))
  (.connect ssh-client host-address :username "jslee" :password password :port host-port)

  ;; fetch the remote inventory
  (setv folders (ssh-client get-remote-directories))
  (setv remote-inventory (get-remote-inventory ssh-client folders))

  ;; fetch the local inventory
  (setv local-inventory (get-local-inventory))
  (setv (, in-local-not-in-remote in-remote-not-in-local) (diff-directories local-inventory remote-inventory))

  ;; make the missing directories on both local and remote
  (make-missing-local-directory (list (.keys remote-inventory)))
  (make-missing-remote-directory ssh-client (list (.keys local-inventory)))

  ;; make an scp-client based on the ssh-client above
  (setv scp-client (SCPClient (.get-transport ssh-client) :socket-timeout 100000000))

  ;; sync using scp
  (exec-scp scp-client in-local-not-in-remote in-remote-not-in-local)

  ;; log out
  (.close ssh-client))
