package com.booster.personallocation.service;

import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.dto.LocationResponse;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class PersonalLocationService {

    private final PersonalLocationRepository personalLocationRepository;
    private final UserRepository userRepository;

    /** 최초 1회 등록. 이미 등록되어 있으면 409. */
    @Transactional
    public LocationResponse register(Long userId, LocationRequest request) {
        requireActive(userId); // (BS-30 7차 F3) 탈퇴 계정 쓰기 차단
        if (personalLocationRepository.existsById(userId)) {
            throw BusinessException.conflict("LOCATION_ALREADY_REGISTERED",
                    "이미 등록된 위치가 있습니다. 수정 API를 사용하세요.");
        }
        try {
            PersonalLocation saved = personalLocationRepository.save(PersonalLocation.create(
                    userId, request.lat(), request.lng(), request.radiusMeters(), request.placeName()));
            return LocationResponse.from(saved);
        } catch (DataIntegrityViolationException e) {
            // (BS-30 7차 C#7) 동시 등록 레이스 → PK 위반을 도메인 에러로 변환(일반 500/DATA_CONFLICT 대신).
            throw BusinessException.conflict("LOCATION_ALREADY_REGISTERED",
                    "이미 등록된 위치가 있습니다. 수정 API를 사용하세요.");
        }
    }

    /** 등록된 위치 수정. 미등록 시 404. */
    @Transactional
    public LocationResponse update(Long userId, LocationRequest request) {
        requireActive(userId); // (BS-30 7차 F3) 탈퇴 계정 쓰기 차단
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));
        location.update(request.lat(), request.lng(), request.radiusMeters(), request.placeName());
        return LocationResponse.from(location);
    }

    private void requireActive(Long userId) {
        if (!userRepository.existsByIdAndActiveTrue(userId)) {
            throw BusinessException.forbidden("INACTIVE_USER", "비활성(탈퇴) 계정입니다.");
        }
    }

    @Transactional(readOnly = true)
    public LocationResponse get(Long userId) {
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));
        return LocationResponse.from(location);
    }
}
