// Copyright Jetstack Ltd. See LICENSE for details.
package instance_pool

import (
	"testing"

	"github.com/Sirupsen/logrus"
	"github.com/golang/mock/gomock"

	clusterv1alpha1 "github.com/jetstack/tarmak/pkg/apis/cluster/v1alpha1"
	"github.com/jetstack/tarmak/pkg/tarmak/mocks"
	"github.com/jetstack/tarmak/pkg/tarmak/role"
)

type fakeInstancePool struct {
	*InstancePool
	ctrl *gomock.Controller

	conf       *clusterv1alpha1.InstancePool
	rootVolume *Volume

	fakeCluster     *mocks.MockCluster
	fakeEnvironment *mocks.MockEnvironment
	fakeProvider    *mocks.MockProvider
}

func newFakeInstancePool(t *testing.T) *fakeInstancePool {
	i := &fakeInstancePool{
		conf:         &clusterv1alpha1.InstancePool{},
		ctrl:         gomock.NewController(t),
		InstancePool: &InstancePool{},
	}

	i.fakeCluster = mocks.NewMockCluster(i.ctrl)
	i.fakeEnvironment = mocks.NewMockEnvironment(i.ctrl)
	i.fakeProvider = mocks.NewMockProvider(i.ctrl)

	i.fakeCluster.EXPECT().Log().AnyTimes().Return(logrus.NewEntry(logrus.New()))
	i.fakeCluster.EXPECT().Environment().AnyTimes().Return(i.fakeEnvironment)
	i.fakeEnvironment.EXPECT().Provider().AnyTimes().Return(i.fakeProvider)
	i.fakeProvider.EXPECT().InstanceType(gomock.Any()).AnyTimes().Return("instanceType", nil)

	i.fakeProvider.EXPECT().VolumeType(gomock.Any()).AnyTimes().Return("gp2", nil)
	i.fakeProvider.EXPECT().Cloud().Return(clusterv1alpha1.CloudAmazon).AnyTimes()
	i.fakeProvider.EXPECT().Name().Return("aws1").AnyTimes()

	volumes := []clusterv1alpha1.Volume{
		clusterv1alpha1.Volume{},
	}
	volumes[0].Name = "root"
	i.conf.Volumes = volumes

	return i
}

func TestInstancePool_MinMaxCount(t *testing.T) {
	i := newFakeInstancePool(t)
	defer i.ctrl.Finish()

	var err error
	var instancePool *InstancePool

	//min = 0,  max = 0 => error
	_, err = i.test_MinMax(0, 0, false)
	if err == nil {
		t.Errorf("expected error, got none")
	}

	//min = n+1 max = n => error
	_, err = i.test_MinMax(4, 3, false)
	if err == nil {
		t.Errorf("expected error, got none")
	}

	//min != max && statefull => error
	_, err = i.test_MinMax(3, 4, true)
	if err == nil {
		t.Errorf("expected error, got none")
	}

	//min = 0 max = n => max == min
	instancePool, err = i.test_MinMax(0, 4, true)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	if instancePool.conf.MaxCount != instancePool.conf.MinCount || instancePool.conf.MaxCount == 0 {
		t.Errorf("expected min and max count to equal 4, got: minCount=%d maxCount=%d", instancePool.conf.MinCount, instancePool.conf.MaxCount)
	}

	//min = n max = 0 => max == min
	instancePool, err = i.test_MinMax(4, 0, true)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	if instancePool.conf.MaxCount != instancePool.conf.MinCount || instancePool.conf.MaxCount == 0 {
		t.Errorf("expected min and max count to equal 4, got: minCount=%d maxCount=%d", instancePool.conf.MinCount, instancePool.conf.MaxCount)
	}

	//min = n max = n => min = n max = n
	instancePool, err = i.test_MinMax(4, 4, true)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	if instancePool.conf.MaxCount != instancePool.conf.MinCount || instancePool.conf.MaxCount != 4 {
		t.Errorf("expected min and max count to equal 4, got: minCount=%d maxCount=%d", instancePool.conf.MinCount, instancePool.conf.MaxCount)
	}

	//min = n max = n+1 && !statefull => min = n max = n+1
	instancePool, err = i.test_MinMax(4, 5, false)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	if instancePool.conf.MaxCount != 5 || instancePool.conf.MinCount != 4 {
		t.Errorf("expected minCount=4 and maxCount=5, got: minCount=%d maxCount=%d", instancePool.conf.MinCount, instancePool.conf.MaxCount)
	}

}

func (i *fakeInstancePool) test_MinMax(min, max int, statefull bool) (instancePool *InstancePool, err error) {
	role := &role.Role{Stateful: statefull}
	i.conf.MinCount = min
	i.conf.MaxCount = max
	i.fakeCluster.EXPECT().Role(gomock.Any()).Times(1).Return(role)
	return NewFromConfig(i.fakeCluster, i.conf)
}
