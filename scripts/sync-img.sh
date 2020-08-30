#!/bin/bash

workdir=`pwd`
log_file=${workdir}/sync_images_$(date +"%Y-%m-%d").log
images_list="tiller,pause,kubernetes-dashboard,k8s-dns-sidecar"
rancher_list="master"
images_arch=amd64
images_namespace=rancher

aliyun_registry=registry.cn-hangzhou.aliyuncs.com  
#aliyun_registry=registry.cn-shanghai.aliyuncs.com  

aliyun_registry1=registry.cn-hangzhou.aliyuncs.com
aliyun_registry2=registry.cn-shenzhen.aliyuncs.com

docker login --username=${ALI_DOCKER_USERNAME}  -p${ALI_DOCKER_PASSWORD} ${aliyun_registry1}
docker login --username=${ALI_DOCKER_USERNAME}  -p${ALI_DOCKER_PASSWORD} ${aliyun_registry2}

docker login -u ${DOCKER_USERNAME} -p ${DOCKER_PASSWORD}

#docker pull rancherlabs/website:build
#docker tag rancherlabs/website:build registry.cn-shenzhen.aliyuncs.com/rancher/website:build
#docker push registry.cn-shenzhen.aliyuncs.com/rancher/website:build

#docker pull hongxiaolu/website:file-download
#docker tag hongxiaolu/website:file-download registry.cn-shenzhen.aliyuncs.com/rancher/website:file-download
#docker push registry.cn-shenzhen.aliyuncs.com/rancher/website:file-download

logger()
{
    log=$1
    cur_time='['$(date +"%Y-%m-%d %H:%M:%S")']'
    echo ${cur_time} ${log} | tee -a ${log_file}
}

docker_push ()
{
    gcr_namespace=$1
    img_tag=$2
    rancher_namespace=$3

    docker pull gcr.io/${gcr_namespace}/${img_tag}
    docker tag gcr.io/${gcr_namespace}/${img_tag} ${aliyun_registry}/${rancher_namespace}/${img_tag}
    docker push ${aliyun_registry}/${rancher_namespace}/${img_tag}

    if [ $? -ne 0 ]; then
        logger "synchronized the ${aliyun_registry}/${rancher_namespace}/${img_tag} failed."
        exit -1
    else
        logger "synchronized the ${aliyun_registry}/${rancher_namespace}/${img_tag} successfully."
        return 0
    fi
}

sync_images_with_arch ()
{
    img_list=$1
    img_arch=$2
    img_namespace=$3

    for imgs in $(echo ${img_list} | tr "," "\n");
    do
        if [ "x${imgs}" == "xtiller" ]; then
            kube_tags=$(curl -k -s -X GET https://gcr.io/v2/kubernetes-helm/${imgs}/tags/list | jq -r '.tags[]'| sort -r | head -n 5 | grep -v rc )
            rancher_result=$(curl -k -s -X GET https://registry.hub.docker.com/v2/repositories/${img_namespace}/${imgs}/tags/ | jq '.["detail"]' | sed 's/\"//g' | awk '{print $2}' | head -n 5 | grep -v rc | grep -v dev )

            if [ "x${rancher_result}" == "xnot" ]; then
                for tags in ${kube_tags}
                do
                    docker_push "kubernetes-helm" ${imgs}:${tags} ${img_namespace}
                done
            else
                rancher_tags=$(curl -k -s -X GET https://registry.hub.docker.com/v2/repositories/${img_namespace}/${imgs}/tags/?page_size=1000 | jq '."results"[]["name"]' | sort -r | sed 's/\"//g' | head -n 5 | grep -v rc | grep -v dev )
                for tags in ${kube_tags}
                do
                    if echo "${rancher_tags[@]}" | grep -w "${tags}" &>/dev/null; then
                        logger "The image ${imgs}:${tags} has been synchronized and skipped."
                    else
                        docker_push "kubernetes-helm" ${imgs}:${tags} ${img_namespace}
                    fi
                done
            fi
        else
            kube_tags=$(curl -k -s -X GET https://gcr.io/v2/google_containers/${imgs}-${img_arch}/tags/list | jq -r '.tags[]'|sort -r | head -n 5 | grep -v rc | grep -v dev )
            rancher_result=$(curl -k -s -X GET https://registry.hub.docker.com/v2/repositories/${img_namespace}/${imgs}-${img_arch}/tags/ | jq '.["detail"]' | sed 's/\"//g' | awk '{print $2}' | head -n 5 | grep -v rc | grep -v dev )

            if [ "x${rancher_result}" == "xnot" ]; then
                for tags in ${kube_tags}
                do
                    docker_push "google_containers" ${imgs}-${img_arch}:${tags} ${img_namespace}
                done
            else
                rancher_tags=$(curl -k -s -X GET https://registry.hub.docker.com/v2/repositories/${img_namespace}/${imgs}-${img_arch}/tags/?page_size=1000 | jq '."results"[]["name"]' | sort -r |sed 's/\"//g' | head -n 5 | grep -v rc | grep -v dev )
                for tags in ${kube_tags}
                do
                    if  echo "${rancher_tags[@]}" | grep -w "${tags}" &>/dev/null; then
                        logger "The image ${imgs}-${img_arch}:${tags} has been synchronized and skipped."
                    else
                        docker_push "google_containers" ${imgs}-${img_arch}:${tags} ${img_namespace}
                    fi
                done
            fi
        fi
    done

    logger 'Completed to synchronize.'

    return 0
}

#main process
#jq_install_check
#docker_install_check
#docker_login_check
sync_images_with_arch ${images_list} ${images_arch} ${images_namespace}
