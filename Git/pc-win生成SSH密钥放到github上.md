### **第一步：生成 SSH 密钥**

首先，我们需要在你的电脑上生成一对密钥（一把公钥给 GitHub，一把私钥留在电脑里）。

1. 打开终端（Windows 用户可以使用 Git Bash，Mac 用户直接用 Terminal）。

2. 复制并运行以下命令（

   注意

   ：请将引号内的邮箱换成你注册 GitHub 时用的邮箱）：

   bash

   

   ```
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```

3. 操作提示

   ：

   - 运行后，系统会提示 `Enter file in which to save the key`，直接按 **回车键**（使用默认路径）。
   - 接着提示 `Enter passphrase`，建议直接按 **回车键** 留空（这样以后操作完全免密）。如果你担心私钥泄露，也可以设置一个密码，但每次推送代码时都需要输入这个密码。

### **第二步：获取并复制公钥**

密钥生成后，我们需要把“公钥”的内容复制出来。

1. 在终端中运行以下命令查看公钥内容：

   bash

   

   ```
   cat ~/.ssh/id_ed25519.pub
   ```

2. 关键动作

   ：

   - 你会看到一串以 `ssh-ed25519` 开头的长字符。
   - **全选并复制** 这串字符（注意不要多复制空格或换行，也不要少复制）。

### **第三步：添加到 GitHub**

现在把这把“钥匙”交给 GitHub。

1. 登录 GitHub，点击右上角头像 -> **Settings**。

2. 在左侧菜单栏找到并点击 **SSH and GPG keys**。

3. 点击绿色的 **New SSH key** 按钮。

4. 填写信息

   ：

   - **Title**: 填个名字方便识别，比如 `My Laptop` 或 `Work PC`。
   - **Key**: 把刚才复制的那串 `ssh-ed25519...` 字符粘贴进去。

5. 点击 **Add SSH key** 保存。如果系统提示输入密码，请输入你的 GitHub 登录密码确认。

### **第四步：测试连接**

我们要验证一下配置是否成功。

1. 回到终端，运行：

   bash

   

   ```
   ssh -T git@github.com
   ```

2. 结果判断

   ：

   - 第一次连接时，可能会问 `Are you sure you want to continue connecting (yes/no/[fingerprint])?`，输入 `yes` 并回车。
   - 如果看到 **`Hi <你的用户名>! You've successfully authenticated...`**，恭喜你！配置成功了。

### **第五步：使用 SSH 克隆代码**

最后，用新的方式把代码拉取下来。

1. 使用 SSH 地址进行克隆（注意地址格式变了）：

   bash

   

   ```
   git clone git@github.com:wyzelabs-inc/Bulb_Cam_Pro.git
   ```

2. 进入目录开始你的开发吧！以后所有的 `git push` 操作都将自动完成，不再需要输入密码。
