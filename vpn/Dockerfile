# Start from an official Arch Linux base image
FROM archlinux:latest

# Update packages and install any desired packages.
# In this example, we install the base-devel group as well;
# adjust as needed.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git zsh && \
    # Cleaning up cached package data to keep the image slim
    pacman -Scc --noconfirm

# Install yay
RUN cd /tmp;
    git clone https://aur.archlinux.org/yay.git
    makepkg -si

# Install expressvpn
RUN yay -S expressvpn

# Set a default command to execute when creating a new container
CMD ["/bin/bash"]
